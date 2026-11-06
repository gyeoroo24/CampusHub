"""Health check, the caller's own profile, other users' public profiles, and admin account controls."""
from datetime import datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, Field

from .. import otp
from ..auth import CurrentUser, current_user, current_user_allow_deactivated, optional_user
from ..common import Contact, forbidden, like_pattern, not_found, search_text, set_clause, text
from ..config import get_settings
from ..db import get_conn
from ..permissions import log_moderation
from .moderators import notify_role_change

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


# E.164: + country code + number, 8 to 15 digits in all. India (+91) numbers are 10 digits from 6-9.
PHONE_PATTERN = r"^\+[1-9][0-9]{7,14}$"


def _check_phone(phone: str) -> str:
    if phone.startswith("+91") and not (len(phone) == 13 and phone[3] in "6789"):
        raise HTTPException(422, "An Indian mobile number has 10 digits and starts with 6, 7, 8 or 9.")
    return phone


class ProfileUpdate(BaseModel):
    name: text(100) | None = None
    phone: None = Field(None, description="Only null (removes it). A new number is set by verifying it: "
                                          "POST /me/phone/code, then POST /me/phone/verify")
    department_id: UUID | None = None
    programme: str | None = Field(None, max_length=100)
    graduation_year: int | None = Field(None, ge=1950, le=2100)


class PhoneIn(BaseModel):
    phone: str = Field(pattern=PHONE_PATTERN, description="E.164, e.g. +919876543210")


class PhoneVerify(PhoneIn):
    code: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")


class PublicProfile(BaseModel):
    id: UUID
    name: str
    department_id: UUID | None
    programme: str | None
    graduation_year: int | None
    contact: Contact | None = Field(None, description="Email and phone; only shown to signed-in users")


class AccountUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")   # admin changes go through POST /users/{id}/make-admin
    is_active: bool = Field(description="false deactivates the account: every request it makes gets 403")


_STATUS_COLUMNS = "id, email::text AS email, name, is_active, base_role = 'admin' AS is_admin"


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


@router.post("/me/phone/code", status_code=204, summary="Text a code to a phone number I want on my profile")
async def request_phone_code(body: PhoneIn, user: CurrentUser = Depends(current_user)):
    otp.request_phone_otp(str(user.id), _check_phone(body.phone))
    return Response(status_code=204)


@router.post("/me/phone/verify", response_model=MyProfile,
             summary="Check the code and save the phone number on my profile")
async def verify_phone_code(body: PhoneVerify, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
    otp.verify_phone_otp(str(user.id), _check_phone(body.phone), body.code)
    await conn.execute("UPDATE users SET phone = $2 WHERE id = $1", user.id, body.phone)
    return await _my_profile(conn, user.id)


class UserMatch(BaseModel):
    id: UUID
    name: str
    email: str
    programme: str | None


@router.get("/users/search", response_model=list[UserMatch],
            summary="Find people by name or email, to start a chat (signed-in users)")
async def search_users(q: str = Query(..., min_length=2, max_length=100), limit: int = Query(20, ge=1, le=50),
                       user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    """Active accounts other than mine whose name or email contains q. Names that start with q come first.

    Only people who have signed in to CampusHub are listed: rows made by the local dev seed (cognito_sub
    "dev|...") were never signed in on the deployed app, so they can't receive messages. Dev auth lists
    everyone, since every local account is a dev row."""
    q = search_text(q) or ""
    if len(q) < 2:
        return []
    rows = await conn.fetch(
        """SELECT id, name, email::text AS email, programme FROM users
            WHERE is_active AND id <> $1
              AND ($4::bool OR cognito_sub NOT LIKE 'dev|%')
              AND (name ILIKE '%' || $2 || '%' ESCAPE '\' OR email::text ILIKE '%' || $2 || '%' ESCAPE '\')
            ORDER BY (name ILIKE $2 || '%' ESCAPE '\') DESC, (email::text ILIKE $2 || '%' ESCAPE '\') DESC, name
            LIMIT $3""", user.id, like_pattern(q), limit, get_settings().auth_mode == "dev")
    return [UserMatch(**dict(r)) for r in rows]


@router.get("/users/lookup", response_model=AccountStatus, summary="Find an account by email (admin)")
async def lookup_user(email: str = Query(..., min_length=3, max_length=320),
                      user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    """The admin's account tools work by email; this turns an email into the account and its status."""
    if not user.is_admin:
        raise forbidden("Only the admin can look up accounts.")
    row = await conn.fetchrow(f"SELECT {_STATUS_COLUMNS} FROM users WHERE email = $1", email.strip())
    if row is None:
        raise HTTPException(404, "No account with that email. The person needs to sign in to CampusHub once first.")
    return AccountStatus(**dict(row))


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
              summary="Deactivate or reactivate an account (admin)")
async def update_account(user_id: UUID, body: AccountUpdate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    if not user.is_admin:
        raise forbidden("Only the admin can change accounts.")
    if user_id == user.id:
        raise HTTPException(422, "You can't deactivate your own account; hand the admin role over first.")
    async with conn.transaction():
        if not body.is_active:
            row = await _deactivate(conn, user_id, by=user.id)
        else:
            row = await conn.fetchrow(
                f"""UPDATE users SET is_active = true WHERE id = $1 RETURNING {_STATUS_COLUMNS}""", user_id)
        if row is None:
            raise not_found("User")
        await log_moderation(conn, user.id, "reactivate_user" if body.is_active else "deactivate_user", "user", user_id)
    return AccountStatus(**dict(row))


async def _deactivate(conn: asyncpg.Connection, user_id: UUID, by: UUID) -> asyncpg.Record | None:
    """Deactivate an account (a suspension, not a deletion: the owner can reactivate it by signing
    in again, see reactivate_me) and end its moderator roles -- an admin has to grant any role again
    after reactivation. Their posts and messages stay, marked as coming from a deactivated account.
    Call inside a transaction."""
    row = await conn.fetchrow(
        f"""UPDATE users SET is_active = false WHERE id = $1 RETURNING {_STATUS_COLUMNS}""", user_id)
    if row is not None:
        await conn.execute(
            """UPDATE moderator_assignments SET revoked_at = now(), revoked_by = $2
               WHERE user_id = $1 AND revoked_at IS NULL""", user_id, by)
    return row


@router.post("/me/deactivate", status_code=204,
             summary="Deactivate my own account: a suspension, not a deletion -- signing in again reactivates it")
async def deactivate_me(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    if user.is_admin:
        raise HTTPException(422, "The admin can't deactivate their own account. Hand the admin role over first.")
    async with conn.transaction():
        await _deactivate(conn, user.id, by=user.id)
        await log_moderation(conn, user.id, "deactivate_user", "user", user.id)
    return Response(status_code=204)


# Registered in main.py WITHOUT the blanket `optional_user` dependency every other router gets:
# that dependency 403s a deactivated account outright, which is exactly the one request that has
# to work for it anyway, so it can sign back in.
reactivate_router = APIRouter(tags=["Users"])


@reactivate_router.post("/me/reactivate", response_model=MyProfile,
             summary="Reactivate my deactivated account and sign me back in (after I confirm)")
async def reactivate_me(pair: tuple[CurrentUser, bool] = Depends(current_user_allow_deactivated),
                        conn: asyncpg.Connection = Depends(get_conn)):
    user, was_deactivated = pair
    if was_deactivated:
        async with conn.transaction():
            await conn.execute("UPDATE users SET is_active = true WHERE id = $1", user.id)
            await log_moderation(conn, user.id, "reactivate_user", "user", user.id)
    return await _my_profile(conn, user.id)


@router.post("/users/{user_id}/make-admin", response_model=AccountStatus,
             summary="Hand the admin role to someone else (admin); you become a signed-in user")
async def make_admin(user_id: UUID, background: BackgroundTasks, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    """There is exactly one admin. The current admin names their successor; in one transaction the
    successor becomes admin and the caller is downgraded to a normal signed-in user."""
    if not user.is_admin:
        raise forbidden("Only the admin can make someone else the admin.")
    if user_id == user.id:
        raise HTTPException(422, "You are already the admin.")
    async with conn.transaction():
        # Lock the caller's row: if two hand-overs race, the second sees it's no longer admin.
        still_admin = await conn.fetchval(
            "SELECT base_role = 'admin' FROM users WHERE id = $1 FOR UPDATE", user.id)
        if not still_admin:
            raise forbidden("You are no longer the admin.")
        target = await conn.fetchrow("SELECT is_active FROM users WHERE id = $1 FOR UPDATE", user_id)
        if target is None:
            raise not_found("User")
        if not target["is_active"]:
            raise HTTPException(422, "This account is deactivated; reactivate it before making it the admin.")
        # Demote first: the database allows only one admin row at a time.
        await conn.execute("UPDATE users SET base_role = 'signed_in' WHERE id = $1", user.id)
        row = await conn.fetchrow(
            f"UPDATE users SET base_role = 'admin' WHERE id = $1 RETURNING {_STATUS_COLUMNS}", user_id)
        await log_moderation(conn, user.id, "transfer_admin", "user", user_id)
        await notify_role_change(conn, background, user_id,
                                 f"{user.name or 'The previous admin'} made you the CampusHub admin.")
    return AccountStatus(**dict(row))
