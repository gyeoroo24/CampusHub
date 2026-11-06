"""Seller trust score (future plan §1.5): a seller's own strike history and appeal, and the Buy &
Sell moderator side (the contested-appeal queue, overturn a strike, reject an appeal, lift a
suspension, unblock a seller and the unblock-request queue).

The "Negative Seller" / "Blocked Seller" tag, and whether a listing is hidden pending review, are
computed from this data and shown on listings - see app.seller_trust.seller_trust_tags and
app.routers.listings. Strikes are created only by POST /reports/{id}/resolve
(app.routers.reports), never here.
"""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user
from ..config import get_settings
from ..common import UserRef, forbidden, not_found, text
from ..db import get_conn
from ..permissions import is_module_moderator, log_moderation
from ..seller_trust import (AppealStatus, Severity, Tag, appeal_status, file_appeal, is_listing_suspended, lift_suspension,
                            overturn_strike, seller_trust_tags)
from ..seller_trust import file_unblock_request, is_blocked, reject_unblock_request, unblock_seller
from ..seller_trust import reject_appeal as _reject_appeal

router = APIRouter(tags=["Seller trust score"])

_SELECT = """
SELECT s.id, s.seller_id, u.name AS seller_name, s.listing_id,
       coalesce(l.title, s.listing_title, 'Deleted listing') AS listing_title,
       COALESCE(l.hidden_by_strike_id = s.id, false) AS listing_hidden, s.severity::text AS severity,
       s.moderator_note, s.excluded, s.appeal_message, s.appeal_created_at,
       s.appeal_resolved_at, s.created_at
FROM seller_strikes s LEFT JOIN listings l ON l.id = s.listing_id JOIN users u ON u.id = s.seller_id
"""


class StrikeOut(BaseModel):
    id: UUID
    seller: UserRef
    listing_id: UUID | None = Field(description="Null once the seller deleted the listing")
    listing_title: str
    listing_hidden: bool = Field(description="True if this strike is the reason the listing is "
                                             "currently hidden (it hasn't been overturned yet).")
    severity: Severity
    moderator_note: str | None
    excluded: bool = Field(description="True if a moderator overturned this strike; it no longer counts.")
    appeal_message: str | None
    appeal_created_at: datetime | None
    appeal_status: AppealStatus = Field(description="'none' (no appeal filed), 'pending' (needs a "
                                                     "moderator), 'rejected' or 'overturned'.")
    created_at: datetime


class AppealIn(BaseModel):
    message: text(1000)


class OverturnIn(BaseModel):
    note: text(1000, min_length=0) | None = None


def _strike(r: asyncpg.Record) -> StrikeOut:
    return StrikeOut(
        id=r["id"], seller=UserRef(id=r["seller_id"], name=r["seller_name"]), listing_id=r["listing_id"],
        listing_title=r["listing_title"], listing_hidden=r["listing_hidden"], severity=r["severity"],
        moderator_note=r["moderator_note"], excluded=r["excluded"], appeal_message=r["appeal_message"],
        appeal_created_at=r["appeal_created_at"],
        appeal_status=appeal_status(r["appeal_message"], r["appeal_resolved_at"], r["excluded"]),
        created_at=r["created_at"])


async def _require_buy_sell_moderator(conn: asyncpg.Connection, user: CurrentUser) -> None:
    if not await is_module_moderator(conn, user, "buy_sell"):
        raise forbidden("Only a Buy & Sell moderator or admin can do this.")


@router.get("/me/seller-strikes", response_model=list[StrikeOut], summary="My seller-trust strike history")
async def my_strikes(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(_SELECT + " WHERE s.seller_id = $1 ORDER BY s.created_at DESC", user.id)
    return [_strike(r) for r in rows]


class StrikeSummary(BaseModel):
    strikes: int = Field(description="Strikes that count (not overturned), both tiers")
    severe: int
    non_severe: int
    limit: int = Field(description="Non-severe strikes that block posting (one severe strike does it at once)")
    negative_at: int = Field(description="Non-severe strikes that show the Negative Seller tag")
    severe_limit: int
    tag: Tag | None
    suspended: bool = Field(description="Whether I can't post listings right now")


@router.get("/me/seller-strikes/summary", response_model=StrikeSummary,
            summary="How many strikes I have, and how many it takes to be blocked")
async def my_strike_summary(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    counts = {r["severity"]: r["n"] for r in await conn.fetch(
        """SELECT severity::text AS severity, count(*)::int AS n FROM seller_strikes
           WHERE seller_id = $1 AND excluded = false GROUP BY severity""", user.id)}
    settings = get_settings()
    tags = await seller_trust_tags(conn, {user.id})
    return StrikeSummary(strikes=sum(counts.values()), severe=counts.get("severe", 0),
                         non_severe=counts.get("non_severe", 0), limit=settings.seller_strike_blocked_threshold,
                         negative_at=settings.seller_strike_negative_threshold,
                         severe_limit=settings.seller_strike_severe_threshold, tag=tags.get(user.id),
                         suspended=await is_listing_suspended(conn, user.id))


@router.post("/me/seller-strikes/{strike_id}/appeal", status_code=204,
             summary="Appeal one of my strikes (one appeal per strike)")
async def appeal_strike(strike_id: UUID, body: AppealIn, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    if not await file_appeal(conn, strike_id, user.id, body.message):
        raise HTTPException(409, "This strike doesn't exist, isn't yours, or already has an appeal.")
    return Response(status_code=204)


@router.get("/seller-strikes", response_model=list[StrikeOut],
            summary="Moderator queue: strikes across all sellers (Buy & Sell moderator or admin). "
                    "Defaults to the ones that need a decision - an appeal nobody has resolved yet.")
async def list_strikes(
    appeal_status_filter: Literal["pending", "resolved", "none", "all"] = Query(
        "pending", alias="appeal_status", description="Filter by appeal state; 'pending' is the "
                                                       "actionable queue (an unresolved appeal)."),
    seller_id: UUID | None = Query(None, description="Narrow to one seller's strikes"),
    user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn),
):
    await _require_buy_sell_moderator(conn, user)
    where = {
        "pending": "s.appeal_message IS NOT NULL AND s.appeal_resolved_at IS NULL",
        "resolved": "s.appeal_message IS NOT NULL AND s.appeal_resolved_at IS NOT NULL",
        "none": "s.appeal_message IS NULL",
        "all": "true",
    }[appeal_status_filter]
    rows = await conn.fetch(
        _SELECT + f" WHERE ($1::uuid IS NULL OR s.seller_id = $1) AND {where} "
                  "ORDER BY s.appeal_created_at NULLS LAST, s.created_at DESC",
        seller_id)
    return [_strike(r) for r in rows]


@router.post("/seller-strikes/{strike_id}/overturn", status_code=204,
             summary="Overturn a strike: it stops counting, the listing it hid becomes visible "
                     "again, and it may lift a suspension it caused (Buy & Sell moderator or admin)")
async def overturn(strike_id: UUID, body: OverturnIn, user: CurrentUser = Depends(current_user),
                   conn: asyncpg.Connection = Depends(get_conn)):
    await _require_buy_sell_moderator(conn, user)
    async with conn.transaction():
        seller_id = await overturn_strike(conn, strike_id, user.id, body.note)
        if seller_id is None:
            raise not_found("Strike")
        await log_moderation(conn, user.id, "overturn_seller_strike", "seller_strike", strike_id, body.note)
    return Response(status_code=204)


@router.post("/seller-strikes/{strike_id}/reject-appeal", status_code=204,
             summary="Reject a pending appeal: the strike stands and the listing stays hidden, but "
                     "it drops out of the queue (Buy & Sell moderator or admin)")
async def reject_appeal(strike_id: UUID, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    await _require_buy_sell_moderator(conn, user)
    async with conn.transaction():
        seller_id = await _reject_appeal(conn, strike_id, user.id)
        if seller_id is None:
            raise not_found("Strike with a pending appeal")
        await log_moderation(conn, user.id, "reject_seller_strike_appeal", "seller_strike", strike_id)
    return Response(status_code=204)


@router.post("/users/{seller_id}/lift-listing-suspension", status_code=204,
             summary="Lift a seller's posting suspension without overturning any strike "
                     "(Buy & Sell moderator or admin)")
async def lift_suspension_endpoint(seller_id: UUID, user: CurrentUser = Depends(current_user),
                                   conn: asyncpg.Connection = Depends(get_conn)):
    await _require_buy_sell_moderator(conn, user)
    async with conn.transaction():
        await lift_suspension(conn, seller_id)
        await log_moderation(conn, user.id, "lift_listing_suspension", "user", seller_id)
    return Response(status_code=204)


# ---------------------------------------------------------------- unblocking a seller
UnblockStatus = Literal["pending", "approved", "rejected"]


class UnblockRequestIn(BaseModel):
    message: text(1000)


class UnblockDecisionIn(BaseModel):
    note: text(1000, min_length=0) | None = None


class UnblockRequestOut(BaseModel):
    id: UUID
    seller: UserRef
    message: str
    status: UnblockStatus
    resolution_note: str | None
    created_at: datetime
    resolved_at: datetime | None


class BlockedSeller(BaseModel):
    seller: UserRef
    email: str
    strikes: int = Field(description="Strikes that still count")
    severe: int
    suspended: bool
    suspended_reason: str | None
    pending_request: UnblockRequestOut | None


_REQUEST_SELECT = """
SELECT r.id, r.seller_id, u.name AS seller_name, r.message, r.status, r.resolution_note, r.created_at, r.resolved_at
FROM seller_unblock_requests r JOIN users u ON u.id = r.seller_id
"""


def _request(r: asyncpg.Record) -> UnblockRequestOut:
    return UnblockRequestOut(id=r["id"], seller=UserRef(id=r["seller_id"], name=r["seller_name"]),
                             message=r["message"], status=r["status"], resolution_note=r["resolution_note"],
                             created_at=r["created_at"], resolved_at=r["resolved_at"])


@router.get("/me/seller-unblock-request", response_model=UnblockRequestOut | None,
            summary="My latest request to be unblocked as a seller (null if I never asked)")
async def my_unblock_request(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(_REQUEST_SELECT + " WHERE r.seller_id = $1 ORDER BY r.created_at DESC LIMIT 1", user.id)
    return _request(row) if row else None


@router.post("/me/seller-unblock-request", response_model=UnblockRequestOut, status_code=201,
             summary="Ask the Buy & Sell moderators to unblock me as a seller (only while blocked)")
async def request_unblock(body: UnblockRequestIn, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    if not await is_blocked(conn, user.id):
        raise HTTPException(409, "You aren't blocked as a seller.")
    async with conn.transaction():
        request_id = await file_unblock_request(conn, user.id, body.message)
    if request_id is None:
        raise HTTPException(409, "You already have a request waiting for a moderator.")
    return _request(await conn.fetchrow(_REQUEST_SELECT + " WHERE r.id = $1", request_id))


@router.get("/seller-unblock-requests", response_model=list[UnblockRequestOut],
            summary="Moderator queue: requests to be unblocked (Buy & Sell moderator or admin)")
async def list_unblock_requests(
    status: Literal["pending", "resolved", "all"] = Query("pending"),
    user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn),
):
    await _require_buy_sell_moderator(conn, user)
    where = {"pending": "r.status = 'pending'", "resolved": "r.status <> 'pending'", "all": "true"}[status]
    rows = await conn.fetch(_REQUEST_SELECT + f" WHERE {where} ORDER BY r.created_at DESC LIMIT 200")
    return [_request(r) for r in rows]


@router.get("/blocked-sellers", response_model=list[BlockedSeller],
            summary="Sellers who are blocked right now, with any waiting unblock request (Buy & Sell moderator or admin)")
async def list_blocked_sellers(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    await _require_buy_sell_moderator(conn, user)
    rows = await conn.fetch(
        """SELECT u.id, u.name, u.email::text AS email, u.listing_suspended_at IS NOT NULL AS suspended,
                  u.listing_suspended_reason,
                  count(s.id) FILTER (WHERE s.excluded = false)::int AS strikes,
                  count(s.id) FILTER (WHERE s.excluded = false AND s.severity = 'severe')::int AS severe
           FROM users u LEFT JOIN seller_strikes s ON s.seller_id = u.id
           WHERE u.listing_suspended_at IS NOT NULL
              OR EXISTS (SELECT 1 FROM seller_strikes x WHERE x.seller_id = u.id AND x.excluded = false)
           GROUP BY u.id ORDER BY u.listing_suspended_at DESC NULLS LAST, u.name""")
    tags = await seller_trust_tags(conn, {r["id"] for r in rows})
    blocked = [r for r in rows if r["suspended"] or tags.get(r["id"]) == "blocked"]
    pending = {r["seller_id"]: _request(r) for r in await conn.fetch(
        _REQUEST_SELECT + " WHERE r.status = 'pending' AND r.seller_id = ANY($1::uuid[])", [r["id"] for r in blocked])}
    return [BlockedSeller(seller=UserRef(id=r["id"], name=r["name"]), email=r["email"], strikes=r["strikes"],
                          severe=r["severe"], suspended=r["suspended"], suspended_reason=r["listing_suspended_reason"],
                          pending_request=pending.get(r["id"])) for r in blocked]


@router.post("/users/{seller_id}/unblock", status_code=204,
             summary="Unblock a seller: reset their strikes, lift the posting suspension and approve any waiting "
                     "request; they are notified (Buy & Sell moderator or admin)")
async def unblock(seller_id: UUID, body: UnblockDecisionIn | None = None, user: CurrentUser = Depends(current_user),
                  conn: asyncpg.Connection = Depends(get_conn)):
    await _require_buy_sell_moderator(conn, user)
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)", seller_id):
        raise not_found("User")
    note = body.note if body else None
    async with conn.transaction():
        reset = await unblock_seller(conn, seller_id, user.id, note)
        await log_moderation(conn, user.id, "unblock_seller", "user", seller_id,
                             f"{reset} strikes reset" + (f": {note}" if note else ""))
    return Response(status_code=204)


@router.post("/seller-unblock-requests/{request_id}/approve", status_code=204,
             summary="Approve an unblock request: same as unblocking the seller (Buy & Sell moderator or admin)")
async def approve_unblock_request(request_id: UUID, body: UnblockDecisionIn | None = None,
                                  user: CurrentUser = Depends(current_user),
                                  conn: asyncpg.Connection = Depends(get_conn)):
    await _require_buy_sell_moderator(conn, user)
    seller_id = await conn.fetchval(
        "SELECT seller_id FROM seller_unblock_requests WHERE id = $1 AND status = 'pending'", request_id)
    if seller_id is None:
        raise not_found("Waiting unblock request")
    note = body.note if body else None
    async with conn.transaction():
        reset = await unblock_seller(conn, seller_id, user.id, note)
        await log_moderation(conn, user.id, "approve_unblock_request", "seller_unblock_request", request_id,
                             f"{reset} strikes reset" + (f": {note}" if note else ""))
    return Response(status_code=204)


@router.post("/seller-unblock-requests/{request_id}/reject", status_code=204,
             summary="Decline an unblock request: the seller stays blocked and is told (Buy & Sell moderator or admin)")
async def reject_unblock(request_id: UUID, body: UnblockDecisionIn | None = None,
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    await _require_buy_sell_moderator(conn, user)
    note = body.note if body else None
    async with conn.transaction():
        if await reject_unblock_request(conn, request_id, user.id, note) is None:
            raise not_found("Waiting unblock request")
        await log_moderation(conn, user.id, "reject_unblock_request", "seller_unblock_request", request_id, note)
    return Response(status_code=204)
