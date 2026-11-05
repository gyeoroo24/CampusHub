"""Grant and revoke moderator roles (FR-3, §3.1).

Admins can grant any role. A department moderator (Academic Help) can grant and revoke
course moderators for courses in their own department. Any moderator can step down by
revoking their own role. The person is notified when a role is given to them or taken away.
"""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, model_validator

from ..auth import CurrentUser, current_user, is_iisc_email
from ..cognito_accounts import AccountCheckUnavailable, signin_account_problem
from ..common import forbidden, not_found
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import can_manage_department, log_moderation

router = APIRouter(prefix="/moderators", tags=["Moderators"])

Module = Literal["buy_sell", "lost_found", "academic_help", "placement_hub", "events"]


MODULE_NAMES = {"buy_sell": "Buy & Sell", "lost_found": "Lost & Found", "academic_help": "Academic Help",
                "placement_hub": "Placement Hub", "events": "Events"}


async def role_label(conn: asyncpg.Connection, module: str, scope_type: str, department_id: UUID | None,
                     course_id: UUID | None) -> str:
    """e.g. "Buy & Sell moderator", "Academic Help moderator for CDS", "... for DS252 (Cloud Computing)"."""
    label = f"{MODULE_NAMES.get(module, module)} moderator"
    if scope_type == "department" and department_id:
        name = await conn.fetchval("SELECT name FROM departments WHERE id = $1", department_id)
        return f"{label} for {name}" if name else label
    if scope_type == "course" and course_id:
        course = await conn.fetchrow("SELECT code, name FROM courses WHERE id = $1", course_id)
        return f"{label} for {course['code']} ({course['name']})" if course else label
    return label


async def notify_role_change(conn: asyncpg.Connection, background: BackgroundTasks, user_id: UUID,
                             message: str) -> None:
    payload = {"message": message, "kind": "role_change"}
    await create_notifications(conn, [user_id], "moderation_action", payload)
    background.add_task(deliver_push, [user_id], "moderation_action", payload)


class GrantCreate(BaseModel):
    email: str = Field(description="IISc email of the user to make a moderator (they must have signed in once)")
    module: Module
    scope_type: Literal["module", "department", "course"] = "module"
    department_id: UUID | None = None
    course_id: UUID | None = None

    @model_validator(mode="after")
    def _shape(self):
        self.email = self.email.strip()
        if not is_iisc_email(self.email):
            raise ValueError("email must be an IISc address")
        if self.module == "academic_help":
            if self.scope_type == "department" and (self.department_id is None or self.course_id is not None):
                raise ValueError("a department grant needs department_id only")
            if self.scope_type == "course" and (self.course_id is None or self.department_id is not None):
                raise ValueError("a course grant needs course_id only")
            if self.scope_type == "module":
                raise ValueError("Academic Help grants are per department or per course")
        elif self.scope_type != "module" or self.department_id or self.course_id:
            raise ValueError("this module only has module-wide grants")
        return self


class Grant(BaseModel):
    id: UUID
    user_id: UUID
    user_email: str
    user_name: str
    module: str
    scope_type: str
    department_id: UUID | None
    course_id: UUID | None
    granted_by: UUID
    granted_at: datetime
    revoked_at: datetime | None


_GRANT_SELECT = """
SELECT m.id, m.user_id, u.email::text AS user_email, u.name AS user_name, m.module::text AS module,
       m.scope_type::text AS scope_type, m.department_id, m.course_id, m.granted_by, m.granted_at, m.revoked_at
FROM moderator_assignments m JOIN users u ON u.id = m.user_id
"""


async def _may_manage_grant(conn: asyncpg.Connection, user: CurrentUser, module: str, scope_type: str,
                            course_id: UUID | None) -> bool:
    if user.is_admin:
        return True
    if module == "academic_help" and scope_type == "course" and course_id is not None:
        department_id = await conn.fetchval("SELECT department_id FROM courses WHERE id = $1", course_id)
        return department_id is not None and await can_manage_department(conn, user, department_id)
    return False


@router.post("", response_model=Grant, status_code=201, summary="Make someone a moderator")
async def grant(body: GrantCreate, background: BackgroundTasks, user: CurrentUser = Depends(current_user),
                conn: asyncpg.Connection = Depends(get_conn)):
    if not await _may_manage_grant(conn, user, body.module, body.scope_type, body.course_id):
        raise forbidden("Only admins, or department moderators for courses in their department, can grant this.")
    target = await conn.fetchrow("SELECT id, cognito_sub, is_active FROM users WHERE email = $1", body.email)
    if target is None:
        raise HTTPException(404, "No user with that email yet. They need to sign in to CampusHub once first.")
    if not target["is_active"]:
        raise HTTPException(422, "This account is deactivated. Reactivate it before granting a role.")
    try:
        problem = await signin_account_problem(target["cognito_sub"])
    except AccountCheckUnavailable as exc:
        raise HTTPException(503, "Couldn't check this person's sign-in account just now. Try again.") from exc
    if problem is not None:
        raise HTTPException(422, problem)
    target = target["id"]
    try:
        async with conn.transaction():
            grant_id = await conn.fetchval(
                """INSERT INTO moderator_assignments (user_id, module, scope_type, department_id, course_id, granted_by)
                   VALUES ($1, $2, $3, $4, $5, $6) RETURNING id""",
                target, body.module, body.scope_type, body.department_id, body.course_id, user.id)
            await log_moderation(conn, user.id, "grant_moderator", "moderator_assignment", grant_id)
            label = await role_label(conn, body.module, body.scope_type, body.department_id, body.course_id)
            await notify_role_change(conn, background, target,
                                     f"You are now a {label}. Open Moderator Panel from the menu next to your profile.")
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, "This person already has this moderator role.") from exc
    return Grant(**dict(await conn.fetchrow(_GRANT_SELECT + " WHERE m.id = $1", grant_id)))


@router.delete("/{grant_id}", status_code=204,
               summary="Revoke a moderator role (admin; department moderator for course roles; or step down from your own)")
async def revoke(grant_id: UUID, background: BackgroundTasks, user: CurrentUser = Depends(current_user),
                 conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(
        "SELECT user_id, module::text AS module, scope_type::text AS scope_type, department_id, course_id, revoked_at "
        "FROM moderator_assignments WHERE id = $1", grant_id)
    if row is None or row["revoked_at"] is not None:
        raise not_found("Active moderator role")
    stepping_down = row["user_id"] == user.id
    if not stepping_down and not await _may_manage_grant(conn, user, row["module"], row["scope_type"],
                                                         row["course_id"]):
        raise forbidden()
    async with conn.transaction():
        # Only an active grant is revoked, so two admins revoking at once can't both succeed.
        if await conn.fetchval(
                "UPDATE moderator_assignments SET revoked_at = now(), revoked_by = $2 "
                "WHERE id = $1 AND revoked_at IS NULL RETURNING id", grant_id, user.id) is None:
            raise not_found("Active moderator role")
        await log_moderation(conn, user.id, "step_down_moderator" if stepping_down else "revoke_moderator",
                             "moderator_assignment", grant_id)
        if not stepping_down:
            label = await role_label(conn, row["module"], row["scope_type"], row["department_id"], row["course_id"])
            await notify_role_change(conn, background, row["user_id"], f"You are no longer a {label}.")
    return Response(status_code=204)


@router.get("", response_model=list[Grant], summary="List active moderator roles")
async def list_grants(module: Module | None = None, department_id: UUID | None = None,
                      course_id: UUID | None = None, include_revoked: bool = Query(False),
                      user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    """Admins see every role. Department moderators see the course moderators in their departments."""
    if user.is_admin:
        visible_departments = None
    else:
        visible_departments = await conn.fetch(
            "SELECT department_id FROM moderator_assignments WHERE user_id = $1 AND scope_type = 'department' "
            "AND revoked_at IS NULL", user.id)
        if not visible_departments:
            raise forbidden("Only admins and department moderators can list moderators.")
        visible_departments = [r["department_id"] for r in visible_departments]
    rows = await conn.fetch(
        _GRANT_SELECT + """
        LEFT JOIN courses c ON c.id = m.course_id
        WHERE ($1::bool OR m.revoked_at IS NULL)
          AND ($2::text IS NULL OR m.module::text = $2)
          AND ($3::uuid IS NULL OR m.department_id = $3 OR c.department_id = $3)
          AND ($4::uuid IS NULL OR m.course_id = $4)
          AND ($5::uuid[] IS NULL OR c.department_id = ANY($5::uuid[]))
        ORDER BY m.granted_at DESC, m.id DESC""",
        include_revoked, module, department_id, course_id, visible_departments)
    return [Grant(**dict(r)) for r in rows]
