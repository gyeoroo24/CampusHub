"""Seller trust score: a "Negative Seller" / "Blocked Seller" tag driven purely
by moderator-confirmed listing removals, never by raw report counts.

A strike is recorded only from POST /reports/{id}/resolve (remove_content=true, target=listing) -
see app/routers/reports.py - never from a listing merely being reported. Two severity tiers
(§1.5.2, "Recommended approach for CampusHub"):

  severe tier     (illegal items - drugs, weapons, anything law-enforcement-relevant): one strike
                  is enough for "Blocked Seller" immediately, no warning, posting suspended
                  pending a moderator's manual decision.
  non-severe tier (everything else a moderator removes - prohibited-but-not-dangerous, scammy,
                  duplicate, misleading): a short ladder - 1st strike is a silent record only,
                  2nd shows the "Negative Seller" tag, 3rd shows "Blocked Seller" and suspends
                  posting.

No strike decay by default - unlike high-volume platforms, a CampusHub seller with two confirmed
removals across their whole stay is still a meaningful signal. Thresholds live in Settings
(seller_strike_*) and are a starting proposal, not a final policy decision.

Reversible, not deleted: recording a strike hides the listing (listings.hidden_by_strike_id) -
nobody but the seller and a Buy & Sell moderator/admin can see it - rather than soft-deleting it.
The strike still counts toward the tag/suspension immediately (tamper-proof, never deleted) and the
seller is notified right away. They may file one written appeal per strike; a moderator reviewing
it either overturns it (excluded=true, the listing comes back for everyone, suspension lifts if it
no longer applies) or rejects the appeal (appeal_resolved_at/by stamped, strike and hide stand,
appeal just drops out of the "needs review" queue). A direct DELETE /listings/{id} (the seller's
own, or a moderator acting outside the report flow) is unrelated and stays a permanent soft-delete.
"""
import logging
from typing import Literal
from uuid import UUID

import asyncpg

from .config import get_settings
from .notify import create_notifications

log = logging.getLogger("campushub.seller_trust")

Severity = Literal["severe", "non_severe"]
Tag = Literal["negative", "blocked"]
AppealStatus = Literal["none", "pending", "rejected", "overturned"]


def appeal_status(appeal_message: str | None, appeal_resolved_at, excluded: bool) -> AppealStatus:
    if appeal_message is None:
        return "none"
    if appeal_resolved_at is None:
        return "pending"
    return "overturned" if excluded else "rejected"


def _tag_from_counts(severe: int, non_severe: int) -> Tag | None:
    s = get_settings()
    if severe >= s.seller_strike_severe_threshold or non_severe >= s.seller_strike_blocked_threshold:
        return "blocked"
    if non_severe >= s.seller_strike_negative_threshold:
        return "negative"
    return None


async def seller_trust_tags(conn: asyncpg.Connection, seller_ids: set[UUID]) -> dict[UUID, Tag]:
    """Negative/blocked tags for these sellers, batched for a listings page or a single detail view.
    Only non-overturned strikes count (excluded=false)."""
    if not seller_ids:
        return {}
    rows = await conn.fetch(
        """SELECT seller_id, severity::text AS severity, count(*) AS n
           FROM seller_strikes WHERE seller_id = ANY($1::uuid[]) AND excluded = false
           GROUP BY seller_id, severity""", list(seller_ids))
    counts: dict[UUID, dict[str, int]] = {}
    for r in rows:
        counts.setdefault(r["seller_id"], {})[r["severity"]] = r["n"]
    tags: dict[UUID, Tag] = {}
    for seller_id, c in counts.items():
        tag = _tag_from_counts(c.get("severe", 0), c.get("non_severe", 0))
        if tag:
            tags[seller_id] = tag
    return tags


async def record_strike(conn: asyncpg.Connection, *, report_id: UUID, listing_id: UUID, seller_id: UUID,
                        listing_title: str, severity: Severity, moderator_id: UUID,
                        note: str | None) -> bool:
    """Records the strike, hides the listing (reversible - see overturn_strike), suspends posting
    if this just crossed the blocked threshold, and notifies the seller. Called inside the same
    transaction as the report resolution that triggered it. Returns False (no-op) if this report
    already recorded a strike - resolve_report can't call this twice for the same report, but stays
    safe if it ever did."""
    strike_id = await conn.fetchval(
        """INSERT INTO seller_strikes (seller_id, listing_id, report_id, severity, moderator_id, moderator_note,
                                      listing_title)
           VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (report_id) DO NOTHING RETURNING id""",
        seller_id, listing_id, report_id, severity, moderator_id, note, listing_title)
    if strike_id is None:
        return False
    await conn.execute("UPDATE listings SET hidden_by_strike_id = $2 WHERE id = $1", listing_id, strike_id)
    tag = (await seller_trust_tags(conn, {seller_id})).get(seller_id)
    if tag == "blocked":
        await _suspend(conn, seller_id,
                       f"Crossed the seller-trust blocked threshold ({severity} strike).")
    await create_notifications(conn, [seller_id], "moderation_action", {
        "message": f'A moderator removed your listing "{listing_title}" after it was reported'
                   + (f". Reason: {note}" if note else "")
                   + ". It is hidden and this counts as a strike on your seller record; "
                   "you can appeal it from your account (My seller record).",
        "listing_id": str(listing_id), "severity": severity, "strike_id": str(strike_id),
    })
    return True


async def _suspend(conn: asyncpg.Connection, seller_id: UUID, reason: str) -> None:
    await conn.execute(
        "UPDATE users SET listing_suspended_at = now(), listing_suspended_reason = $2 "
        "WHERE id = $1 AND listing_suspended_at IS NULL", seller_id, reason)


async def is_listing_suspended(conn: asyncpg.Connection, seller_id: UUID) -> bool:
    return bool(await conn.fetchval("SELECT listing_suspended_at FROM users WHERE id = $1", seller_id))


def _short(text: str, limit: int = 60) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit - 1].rstrip() + "…"


async def _strike_listing(conn: asyncpg.Connection, strike_id: UUID) -> asyncpg.Record:
    return await conn.fetchrow(
        """SELECT s.seller_id, coalesce(l.title, s.listing_title, 'a deleted listing') AS title, u.name AS seller_name
           FROM seller_strikes s LEFT JOIN listings l ON l.id = s.listing_id JOIN users u ON u.id = s.seller_id
           WHERE s.id = $1""", strike_id)


async def _buy_sell_moderators(conn: asyncpg.Connection) -> list[UUID]:
    return [r["id"] for r in await conn.fetch(
        """SELECT DISTINCT u.id FROM users u
           LEFT JOIN moderator_assignments m ON m.user_id = u.id AND m.module = 'buy_sell' AND m.revoked_at IS NULL
           WHERE u.is_active AND (u.base_role = 'admin' OR m.id IS NOT NULL)""")]


async def file_appeal(conn: asyncpg.Connection, strike_id: UUID, seller_id: UUID, message: str) -> bool:
    """True if recorded. False if the strike doesn't exist, isn't this seller's, or already has an
    appeal (one shot per strike). Buy & Sell moderators and the admin are told there's an appeal to review."""
    result = await conn.execute(
        """UPDATE seller_strikes SET appeal_message = $3, appeal_created_at = now()
           WHERE id = $1 AND seller_id = $2 AND appeal_message IS NULL""",
        strike_id, seller_id, message)
    if result.split()[-1] == "0":
        return False
    item = await _strike_listing(conn, strike_id)
    moderators = [m for m in await _buy_sell_moderators(conn) if m != seller_id]
    await create_notifications(conn, moderators, "moderation_action", {
        "message": f'{item["seller_name"]} contested the strike for "{_short(item["title"])}": '
                   f'"{_short(message, 120)}". Review it in Moderation → Seller strikes.',
        "strike_id": str(strike_id), "kind": "strike_appeal"})
    return True


async def overturn_strike(conn: asyncpg.Connection, strike_id: UUID, moderator_id: UUID,
                          note: str | None) -> UUID | None:
    """Excludes the strike from counting, restores the listing it hid, resolves any pending appeal,
    and lifts the seller's suspension if it no longer applies. Returns the seller_id, or None if
    the strike doesn't exist or was already overturned."""
    row = await conn.fetchrow(
        """UPDATE seller_strikes SET excluded = true, excluded_by = $2, excluded_at = now(), excluded_note = $3
           WHERE id = $1 AND excluded = false
           RETURNING seller_id, listing_id, appeal_message IS NOT NULL AND appeal_resolved_at IS NULL AS had_pending_appeal""",
        strike_id, moderator_id, note)
    if row is None:
        return None
    if row["had_pending_appeal"]:
        await conn.execute(
            "UPDATE seller_strikes SET appeal_resolved_at = now(), appeal_resolved_by = $2 WHERE id = $1",
            strike_id, moderator_id)
    await conn.execute(
        "UPDATE listings SET hidden_by_strike_id = NULL WHERE id = $1 AND hidden_by_strike_id = $2",
        row["listing_id"], strike_id)
    seller_id = row["seller_id"]
    tag = (await seller_trust_tags(conn, {seller_id})).get(seller_id)
    if tag != "blocked":
        await lift_suspension(conn, seller_id, notify=False)
    item = await _strike_listing(conn, strike_id)
    await create_notifications(conn, [seller_id], "moderation_action", {
        "message": f'A moderator overturned the strike for "{_short(item["title"])}": it no longer counts and '
                   "the listing is visible again." + (f" Note: {note}" if note else "")
                   + ("" if tag == "blocked" else " You can post listings."),
        "strike_id": str(strike_id), "kind": "strike_overturned"})
    return seller_id


async def reject_appeal(conn: asyncpg.Connection, strike_id: UUID, moderator_id: UUID) -> UUID | None:
    """Marks a pending appeal reviewed and declined: the strike stands and the listing stays
    hidden, but it drops out of the moderator queue. Returns the seller_id, or None if there's no
    strike with a pending appeal at this id."""
    row = await conn.fetchrow(
        """UPDATE seller_strikes SET appeal_resolved_at = now(), appeal_resolved_by = $2
           WHERE id = $1 AND appeal_message IS NOT NULL AND appeal_resolved_at IS NULL
           RETURNING seller_id""",
        strike_id, moderator_id)
    if row is None:
        return None
    item = await _strike_listing(conn, strike_id)
    await create_notifications(conn, [row["seller_id"]], "moderation_action", {
        "message": f'A moderator reviewed your appeal for "{_short(item["title"])}" and kept the strike. '
                   "The listing stays hidden.",
        "strike_id": str(strike_id), "kind": "strike_appeal_rejected"})
    return row["seller_id"]


async def lift_suspension(conn: asyncpg.Connection, seller_id: UUID, notify: bool = True) -> None:
    lifted = await conn.fetchval(
        """UPDATE users SET listing_suspended_at = NULL, listing_suspended_reason = NULL
           WHERE id = $1 AND listing_suspended_at IS NOT NULL RETURNING true""", seller_id)
    if lifted and notify:
        await create_notifications(conn, [seller_id], "moderation_action", {
            "message": "A moderator lifted your posting suspension: you can post listings again.",
            "kind": "suspension_lifted"})


async def is_blocked(conn: asyncpg.Connection, seller_id: UUID) -> bool:
    """Blocked = the "Blocked Seller" tag or a posting suspension (a moderator can lift one without the other)."""
    return (await seller_trust_tags(conn, {seller_id})).get(seller_id) == "blocked" \
        or await is_listing_suspended(conn, seller_id)


async def file_unblock_request(conn: asyncpg.Connection, seller_id: UUID, message: str) -> UUID | None:
    """Records a blocked seller's request to be unblocked and tells the Buy & Sell moderators. None if they
    already have one waiting."""
    request_id = await conn.fetchval(
        """INSERT INTO seller_unblock_requests (seller_id, message) VALUES ($1, $2)
           ON CONFLICT (seller_id) WHERE status = 'pending' DO NOTHING RETURNING id""", seller_id, message)
    if request_id is None:
        return None
    name = await conn.fetchval("SELECT name FROM users WHERE id = $1", seller_id)
    moderators = [m for m in await _buy_sell_moderators(conn) if m != seller_id]
    await create_notifications(conn, moderators, "moderation_action", {
        "message": f'{name} asked to be unblocked as a seller: "{_short(message, 120)}". '
                   "Review it in Moderation → Unblock requests.",
        "request_id": str(request_id), "kind": "unblock_request"})
    return request_id


async def unblock_seller(conn: asyncpg.Connection, seller_id: UUID, moderator_id: UUID,
                         note: str | None) -> int:
    """Unblocks a seller: every strike that still counts is reset (excluded, so the tag goes), any pending
    appeal on them is closed, the posting suspension is lifted and a waiting unblock request is approved. The
    listings those strikes hid stay hidden. The seller is told. Returns how many strikes were reset."""
    reset = await conn.fetch(
        """UPDATE seller_strikes SET excluded = true, excluded_by = $2, excluded_at = now(),
                  excluded_note = coalesce($3, 'Reset when the seller was unblocked'),
                  appeal_resolved_at = CASE WHEN appeal_message IS NOT NULL AND appeal_resolved_at IS NULL
                                            THEN now() ELSE appeal_resolved_at END,
                  appeal_resolved_by = CASE WHEN appeal_message IS NOT NULL AND appeal_resolved_at IS NULL
                                            THEN $2 ELSE appeal_resolved_by END
           WHERE seller_id = $1 AND excluded = false RETURNING id""", seller_id, moderator_id, note)
    await lift_suspension(conn, seller_id, notify=False)
    await conn.execute(
        """UPDATE seller_unblock_requests SET status = 'approved', resolved_by = $2, resolved_at = now(),
                  resolution_note = $3
           WHERE seller_id = $1 AND status = 'pending'""", seller_id, moderator_id, note)
    await create_notifications(conn, [seller_id], "moderation_action", {
        "message": "A moderator unblocked you as a seller and reset your strikes: you can post listings again."
                   + (f" Note: {note}" if note else ""),
        "kind": "seller_unblocked"})
    return len(reset)


async def reject_unblock_request(conn: asyncpg.Connection, request_id: UUID, moderator_id: UUID,
                                 note: str | None) -> UUID | None:
    """Declines a waiting unblock request; the seller stays blocked and is told. Returns the seller_id, or
    None if there's no waiting request with this id."""
    seller_id = await conn.fetchval(
        """UPDATE seller_unblock_requests SET status = 'rejected', resolved_by = $2, resolved_at = now(),
                  resolution_note = $3
           WHERE id = $1 AND status = 'pending' RETURNING seller_id""", request_id, moderator_id, note)
    if seller_id is None:
        return None
    await create_notifications(conn, [seller_id], "moderation_action", {
        "message": "A moderator reviewed your request to be unblocked and kept the block."
                   + (f" Note: {note}" if note else ""),
        "request_id": str(request_id), "kind": "unblock_request_rejected"})
    return seller_id
