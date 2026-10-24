"""Health check, the caller's own profile, other users' public profiles, and admin account controls."""
from datetime import datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user, optional_user
from ..common import Contact, forbidden, not_found, set_clause, text
from ..db import get_conn
from ..permissions import log_moderation

router = APIRouter(tags=["Users"])


@router.get("/health", tags=["Health"], summary="Health check (used by the CloudWatch canary)")
async def health(conn: asyncpg.Connection = Depends(get_conn)) -> dict:
    await conn.fetchval("SELECT 1")
    return {"status": "ok"}


class ModeratorGrant(BaseModel):
    id: UUID
    module: str
    scope_type: str
    department_id: UUID | None
    course_id: UUID | None
    granted_at: datetime


class MyProfile(BaseModel):
    id: UUID
    email: str
    name: str
    phone: str | None
    department_id: UUID | None
    programme: str | None
    graduation_year: int | None
    is_admin: bool
    moderator_grants: list[ModeratorGrant]
    created_at: datetime
    updated_at: datetime


class ProfileUpdate(BaseModel):
    name: text(100) | None = None
    phone: str | None = Field(None, pattern=r"^\+?[0-9]{10,15}$", description="Optional; send null to remove it")
    department_id: UUID | None = None
    programme: str | None = Field(None, max_length=100)
    graduation_year: int | None = Field(None, ge=1950, le=2100)


class PublicProfile(BaseModel):
    id: UUID
    name: str
    department_id: UUID | None
    programme: str | None
    graduation_year: int | None
    contact: Contact | None = Field(None, description="Email and phone; only shown to signed-in users")


class AccountUpdate(BaseModel):
    is_active: bool | None = Field(None, description="false deactivates the account: every request it makes gets 403")
    is_admin: bool | None = None


class AccountStatus(BaseModel):
    id: UUID
    email: str
    name: str
    is_active: bool
    is_admin: bool


async def _my_profile(conn: asyncpg.Connection, user_id: UUID) -> MyProfile:
    row = await conn.fetchrow(
        """SELECT id, email::text AS email, name, phone, department_id, programme, graduation_year,
                  base_role = 'admin' AS is_admin, created_at, updated_at
           FROM users WHERE id = $1""", user_id)
    grants = await conn.fetch(
        """SELECT id, module::text AS module, scope_type::text AS scope_type, department_id, course_id, granted_at
           FROM moderator_assignments WHERE user_id = $1 AND revoked_at IS NULL ORDER BY granted_at""", user_id)
    return MyProfile(**dict(row), moderator_grants=[ModeratorGrant(**dict(g)) for g in grants])


@router.get("/me", response_model=MyProfile, summary="My profile, admin flag and active moderator roles")
async def get_me(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    return await _my_profile(conn, user.id)


@router.patch("/me", response_model=MyProfile, summary="Update my profile")
async def update_me(body: ProfileUpdate, user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    changes = body.model_dump(exclude_unset=True)
    if "name" in changes and changes["name"] is None:
        raise HTTPException(422, "Name can't be empty.")
    sql, values = set_clause(changes, start=2)
    await conn.execute(f"UPDATE users SET {sql} WHERE id = $1", user.id, *values)
    return await _my_profile(conn, user.id)


@router.get("/users/{user_id}", response_model=PublicProfile, summary="Someone's public profile")
async def get_user(user_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                   conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(
        """SELECT id, name, department_id, programme, graduation_year, email::text AS email, phone
           FROM users WHERE id = $1 AND is_active""", user_id)
    if row is None:
        raise not_found("User")
    contact = Contact(email=row["email"], phone=row["phone"]) if viewer else None
    return PublicProfile(id=row["id"], name=row["name"], department_id=row["department_id"],
                         programme=row["programme"], graduation_year=row["graduation_year"], contact=contact)


@router.patch("/users/{user_id}", response_model=AccountStatus,
              summary="Deactivate or reactivate an account, or make someone an admin (admin)")
async def update_account(user_id: UUID, body: AccountUpdate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    if not user.is_admin:
        raise forbidden("Only admins can change accounts.")
    if user_id == user.id:
        raise HTTPException(422, "You can't change your own account status; ask another admin.")
    changes = {}
    if body.is_active is not None:
        changes["is_active"] = body.is_active
    if body.is_admin is not None:
        changes["base_role"] = "admin" if body.is_admin else "signed_in"
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        row = await conn.fetchrow(
            f"""UPDATE users SET {sql} WHERE id = $1
                RETURNING id, email::text AS email, name, is_active, base_role = 'admin' AS is_admin""",
            user_id, *values)
        if row is None:
            raise not_found("User")
        if body.is_active is not None:
            await log_moderation(conn, user.id, "reactivate_user" if body.is_active else "deactivate_user",
                                 "user", user_id)
        if body.is_admin is not None:
            await log_moderation(conn, user.id, "make_admin" if body.is_admin else "remove_admin", "user", user_id)
    return AccountStatus(**dict(row))
