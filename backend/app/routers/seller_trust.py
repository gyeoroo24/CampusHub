"""Seller trust score (future plan §1.5): a seller's own strike history and appeal, and the Buy &
Sell moderator side (the contested-appeal queue, overturn a strike, reject an appeal, lift a
suspension).

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
