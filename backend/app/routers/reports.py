"""User reports: flagging content (a listing selling something prohibited, an abusive comment, ...).

Anyone signed in can report an item once while their report is open. Moderators see the
reports in their own scope and resolve them: "actioned" (optionally removing the content)
or "dismissed". Resolving closes every open report on that same item.

Who sees which reports:
  admin                         all
  Buy & Sell / Lost & Found / Placement Hub moderator    that module's reports
  department moderator          Academic Help reports about their department's courses or forum
  course moderator              Academic Help reports about their course (materials, feedback, forum);
                                they may remove all of these (team decision)
"""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user
from ..common import Page, PageParams, UserRef, forbidden, make_page, not_found, page_params, text
from ..db import get_conn
from ..permissions import log_moderation

router = APIRouter(tags=["Reports & moderation"])

TargetType = Literal["listing", "lost_report", "found_report", "course_material", "course_feedback",
                     "thread", "comment", "interview_experience"]
Module = Literal["buy_sell", "lost_found", "academic_help", "placement_hub"]

# target_type -> (table, column in reports)
TARGETS: dict[str, tuple[str, str]] = {
    "listing": ("listings", "listing_id"),
    "lost_report": ("lost_reports", "lost_report_id"),
    "found_report": ("found_reports", "found_report_id"),
    "course_material": ("course_materials", "course_material_id"),
    "course_feedback": ("course_feedback", "course_feedback_id"),
    "thread": ("threads", "thread_id"),
    "comment": ("comments", "comment_id"),
    "interview_experience": ("interview_experiences", "interview_experience_id"),
}
FIXED_MODULE = {"listing": "buy_sell", "lost_report": "lost_found", "found_report": "lost_found",
                "course_material": "academic_help", "course_feedback": "academic_help",
                "interview_experience": "placement_hub"}
FORUM_MODULE = {"course": "academic_help", "department": "academic_help", "company": "placement_hub"}


class ReportCreate(BaseModel):
    target_type: TargetType
    target_id: UUID
    reason: text(1000)


class ResolveRequest(BaseModel):
    action: Literal["actioned", "dismissed"]
    note: text(1000, min_length=0) | None = None
    remove_content: bool = Field(False, description="With action=actioned, also remove the reported item")


class Report(BaseModel):
    id: UUID
    module: Module
    target_type: TargetType
    target_id: UUID
    reason: str
    status: Literal["open", "actioned", "dismissed"]
    reporter: UserRef | None = Field(None, description="Shown to moderators only")
    created_at: datetime
    handled_at: datetime | None
    resolution_note: str | None


class ResolveResult(BaseModel):
    reports_resolved: int
    content_removed: bool


async def _target_module(conn: asyncpg.Connection, target_type: str, target_id: UUID) -> str:
    """Which module the item belongs to; 404 if it doesn't exist or was already removed."""
    if target_type == "thread":
        scope = await conn.fetchval(
            """SELECT f.scope_type::text FROM threads t JOIN forums f ON f.id = t.forum_id
               WHERE t.id = $1 AND t.deleted_at IS NULL""", target_id)
    elif target_type == "comment":
        scope = await conn.fetchval(
            """SELECT f.scope_type::text FROM comments c JOIN threads t ON t.id = c.thread_id
               JOIN forums f ON f.id = t.forum_id WHERE c.id = $1 AND c.deleted_at IS NULL""", target_id)
    else:
        table, _ = TARGETS[target_type]
        exists = await conn.fetchval(
            f"SELECT EXISTS (SELECT 1 FROM {table} WHERE id = $1 AND deleted_at IS NULL)", target_id)
        scope = "fixed" if exists else None
    if scope is None:
        raise not_found("Reported item")
    return FIXED_MODULE[target_type] if scope == "fixed" else FORUM_MODULE[scope]


async def _moderator_scope(conn: asyncpg.Connection, user: CurrentUser) -> tuple[list[str], list[UUID], list[UUID]]:
    rows = await conn.fetch(
        """SELECT module::text AS module, scope_type::text AS scope_type, department_id, course_id
           FROM moderator_assignments WHERE user_id = $1 AND revoked_at IS NULL""", user.id)
    modules = [r["module"] for r in rows if r["scope_type"] == "module"]
    departments = [r["department_id"] for r in rows if r["department_id"]]
    courses = [r["course_id"] for r in rows if r["course_id"]]
    return modules, departments, courses


# Each report with the course/department its item belongs to (Academic Help), then filtered
# to what the caller moderates. $1 is_admin, $2 module grants, $3 department grants, $4 course grants.
_SCOPED = """
WITH r AS (
    SELECT rp.*, COALESCE(cm.course_id, cf.course_id, fo.course_id) AS scope_course_id,
           fo.department_id AS forum_department_id
    FROM reports rp
    LEFT JOIN course_materials cm ON cm.id = rp.course_material_id
    LEFT JOIN course_feedback cf ON cf.id = rp.course_feedback_id
    LEFT JOIN comments co ON co.id = rp.comment_id
    LEFT JOIN threads th ON th.id = COALESCE(rp.thread_id, co.thread_id)
    LEFT JOIN forums fo ON fo.id = th.forum_id
)
SELECT r.id, r.module::text AS module, r.target_type::text AS target_type, r.target_id, r.reason,
       r.status::text AS status, r.created_at, r.handled_at, r.resolution_note,
       r.reporter_id, u.name AS reporter_name
FROM r
JOIN users u ON u.id = r.reporter_id
LEFT JOIN courses sc ON sc.id = r.scope_course_id
WHERE ($1::bool
       OR (r.module <> 'academic_help' AND r.module::text = ANY($2::text[]))
       OR (r.module = 'academic_help'
           AND (r.scope_course_id = ANY($4::uuid[])
                OR sc.department_id = ANY($3::uuid[])
                OR r.forum_department_id = ANY($3::uuid[]))))
"""


def _report(r: asyncpg.Record, with_reporter: bool = True) -> Report:
    return Report(id=r["id"], module=r["module"], target_type=r["target_type"], target_id=r["target_id"],
                  reason=r["reason"], status=r["status"],
                  reporter=UserRef(id=r["reporter_id"], name=r["reporter_name"]) if with_reporter else None,
                  created_at=r["created_at"], handled_at=r["handled_at"], resolution_note=r["resolution_note"])


@router.post("/reports", response_model=Report, status_code=201, summary="Report content")
async def create_report(body: ReportCreate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    module = await _target_module(conn, body.target_type, body.target_id)
    _, column = TARGETS[body.target_type]
    try:
        report_id = await conn.fetchval(
            f"""INSERT INTO reports (reporter_id, module, target_type, {column}, reason)
                VALUES ($1, $2, $3, $4, $5) RETURNING id""",
            user.id, module, body.target_type, body.target_id, body.reason)
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, "You already have an open report on this item.") from exc
    row = await conn.fetchrow(_SCOPED + " AND r.id = $5", True, [], [], [], report_id)
    return _report(row, with_reporter=False)


@router.get("/me/reports", response_model=Page[Report], summary="Reports I've filed")
async def my_reports(page: PageParams = Depends(page_params), user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(
        _SCOPED + " AND r.reporter_id = $5 ORDER BY r.created_at DESC, r.id DESC LIMIT $6 OFFSET $7",
        True, [], [], [], user.id, page.limit + 1, page.offset)
    return make_page(rows, page, lambda r: _report(r, with_reporter=False))


@router.get("/reports", response_model=Page[Report], summary="Moderation queue (reports in my scope)")
async def list_reports(status: Literal["open", "actioned", "dismissed"] | None = Query("open"),
                       module: Module | None = None, page: PageParams = Depends(page_params),
                       user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    modules, departments, courses = await _moderator_scope(conn, user)
    if not (user.is_admin or modules or departments or courses):
        raise forbidden("Only moderators and admins can see reports.")
    rows = await conn.fetch(
        _SCOPED + """ AND ($5::text IS NULL OR r.status::text = $5) AND ($6::text IS NULL OR r.module::text = $6)
        ORDER BY r.created_at, r.id LIMIT $7 OFFSET $8""",
        user.is_admin, modules, departments, courses, status, module, page.limit + 1, page.offset)
    return make_page(rows, page, _report)


@router.post("/reports/{report_id}/resolve", response_model=ResolveResult,
             summary="Resolve a report (closes every open report on the same item)")
async def resolve_report(report_id: UUID, body: ResolveRequest, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    modules, departments, courses = await _moderator_scope(conn, user)
    row = await conn.fetchrow(_SCOPED + " AND r.id = $5", user.is_admin, modules, departments, courses, report_id)
    if row is None:
        if await conn.fetchval("SELECT EXISTS (SELECT 1 FROM reports WHERE id = $1)", report_id):
            raise forbidden("This report is outside the area you moderate.")
        raise not_found("Report")
    if row["status"] != "open":
        raise HTTPException(409, "This report has already been resolved.")
    if body.remove_content and body.action != "actioned":
        raise HTTPException(422, "remove_content only works with action=actioned.")
    target_type, target_id = row["target_type"], row["target_id"]
    removed = False
    async with conn.transaction():
        # Close the reports first: this locks them, so if another moderator resolves the same item
        # at the same moment, one of the two finds nothing left open and gets 409.
        result = await conn.execute(
            """UPDATE reports SET status = $3, handled_by = $4, handled_at = now(), resolution_note = $5
               WHERE target_type = $1 AND target_id = $2 AND status = 'open'""",
            target_type, target_id, body.action, user.id, body.note)
        resolved = int(result.split()[-1])
        if resolved == 0:
            raise HTTPException(409, "This report has already been resolved.")
        if body.remove_content:
            table, _ = TARGETS[target_type]
            removed = await conn.fetchval(
                f"UPDATE {table} SET deleted_at = now(), deleted_by = $2 WHERE id = $1 AND deleted_at IS NULL "
                "RETURNING true", target_id, user.id) or False
            if removed:
                await log_moderation(conn, user.id, f"remove_{target_type}", target_type, target_id, body.note)
        await log_moderation(conn, user.id, f"report_{body.action}", target_type, target_id, body.note)
    return ResolveResult(reports_resolved=resolved, content_removed=removed)
