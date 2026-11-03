"""Buy & Sell listings (FR-4, FR-5, FR-6, FR-10).

A new listing, or one edited or made available again, alerts matching saved searches and
Wanted posts (app/alerts.py).
"""
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import AfterValidator, BaseModel, Field

from ..alerts import listing_alerts, push_alerts
from ..auth import CurrentUser, current_user, optional_user
from ..common import (MAX_INT_ID, CategoryId, CategoryRef, Contact, Page, PageParams, Photo, UserRef, forbidden,
                      make_page, not_found, page_params, search_text, set_clause, text)
from ..db import get_conn
from ..permissions import close_reports, is_module_moderator, log_moderation
from ..notify import create_notifications, deliver_push
from ..matching.trigger import request_photo_screen
from ..screening import screen_text
from ..seller_trust import Severity, Tag, is_listing_suspended, record_strike, seller_trust_tags
from ..storage import delete_objects, file_url, mark_attached, verify_own_uploads

router = APIRouter(prefix="/listings", tags=["Buy & Sell"])

ListingStatus = Literal["available", "reserved", "sold"]
ListingSort = Literal["newest", "price_asc", "price_desc"]
_ORDER = {"newest": "l.created_at DESC, l.id DESC",
          "price_asc": "l.price ASC, l.created_at DESC, l.id DESC",
          "price_desc": "l.price DESC, l.created_at DESC, l.id DESC"}
MAX_PHOTOS = 10


def _unique_keys(keys: list[str]) -> list[str]:
    if len(set(keys)) != len(keys):
        raise ValueError("photo_keys contains the same photo twice")
    return keys


PhotoKeys = Annotated[list[str], Field(max_length=MAX_PHOTOS), AfterValidator(_unique_keys)]


class ListingCreate(BaseModel):
    title: text(120)
    description: text(5000, min_length=0) | None = None
    price: Decimal = Field(ge=0, max_digits=10, decimal_places=2, description="Rupees")
    category_id: CategoryId
    location: text(200, min_length=0) | None = None
    negotiable: bool = Field(False, description="Show a \"Negotiable\" badge (future plan §2.3)")
    photo_keys: PhotoKeys = Field(default_factory=list,
                                  description="s3_key values from POST /uploads, in display order; first = cover")


class ListingUpdate(BaseModel):
    title: text(120) | None = None
    description: text(5000, min_length=0) | None = None
    price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2)
    category_id: CategoryId | None = None
    location: text(200, min_length=0) | None = None
    negotiable: bool | None = None


class StatusUpdate(BaseModel):
    status: ListingStatus


class PhotosUpdate(BaseModel):
    photo_keys: PhotoKeys = Field(description="The full new photo list, in order")


class ListingSummary(BaseModel):
    id: UUID
    title: str
    price: Decimal
    status: ListingStatus
    location: str | None
    category: CategoryRef
    seller: UserRef
    seller_trust_tag: Tag | None = Field(
        None, description="'negative' or 'blocked', from moderator-confirmed removals against this "
                          "seller (future plan §1.5). Null for everyone else - never a positive badge.")
    hidden: bool = Field(
        False, description="True if a moderator removed this listing while resolving a report "
                           "against it (future plan §1.5) - only the seller and a Buy & Sell "
                           "moderator/admin ever see it true; everyone else never sees this row.")
    held_for_review: bool = Field(
        False, description="Flagged automatically as a possible prohibited item and hidden until a "
                           "moderator decides (future plan §1.6). Seen only by the seller and moderators.")
    negotiable: bool = False
    cover_photo_url: str | None
    created_at: datetime


class ListingDetail(ListingSummary):
    description: str | None
    photos: list[Photo]
    seller_contact: Contact | None = Field(description="Shown to signed-in users only (scenario 1)")
    watching: bool = Field(False, description="The viewer is watching this listing for price changes (§2.3)")
    updated_at: datetime


_SELECT = """
SELECT l.id, l.title, l.description, l.price, l.status::text AS status, l.location,
       l.created_at, l.updated_at, l.seller_id, l.hidden_by_strike_id, l.held_for_review_at, l.negotiable,
       c.id AS category_id, c.name AS category_name,
       u.name AS seller_name, u.email::text AS seller_email, u.phone AS seller_phone, u.is_active AS seller_active,
       (SELECT p.s3_key FROM listing_photos p WHERE p.listing_id = l.id ORDER BY p.sort_order LIMIT 1) AS cover_key
FROM listings l
JOIN bs_categories c ON c.id = l.category_id
JOIN users u ON u.id = l.seller_id
"""


def _summary(r: asyncpg.Record, tag: Tag | None = None) -> ListingSummary:
    return ListingSummary(
        id=r["id"], title=r["title"], price=r["price"], status=r["status"], location=r["location"],
        category=CategoryRef(id=r["category_id"], name=r["category_name"]),
        seller=UserRef(id=r["seller_id"], name=r["seller_name"]), seller_trust_tag=tag,
        hidden=r["hidden_by_strike_id"] is not None,
        held_for_review=r["held_for_review_at"] is not None, negotiable=r["negotiable"],
        cover_photo_url=file_url(r["cover_key"]) if r["cover_key"] else None,
        created_at=r["created_at"])


async def _may_see_hidden(conn: asyncpg.Connection, seller_id: UUID, viewer: CurrentUser | None) -> bool:
    if viewer is None:
        return False
    return viewer.id == seller_id or await is_module_moderator(conn, viewer, "buy_sell")


async def _detail(conn: asyncpg.Connection, listing_id: UUID, viewer: CurrentUser | None) -> ListingDetail:
    r = await conn.fetchrow(_SELECT + " WHERE l.id = $1 AND l.deleted_at IS NULL", listing_id)
    if r is None:
        raise not_found("Listing")
    if ((r["hidden_by_strike_id"] is not None or r["held_for_review_at"] is not None)
            and not await _may_see_hidden(conn, r["seller_id"], viewer)):
        raise not_found("Listing")
    photos = await conn.fetch(
        "SELECT s3_key, sort_order FROM listing_photos WHERE listing_id = $1 ORDER BY sort_order", listing_id)
    tag = (await seller_trust_tags(conn, {r["seller_id"]})).get(r["seller_id"])
    watching = bool(viewer) and await conn.fetchval(
        "SELECT EXISTS (SELECT 1 FROM listing_watches WHERE user_id = $1 AND listing_id = $2)", viewer.id, listing_id)
    return ListingDetail(
        **_summary(r, tag).model_dump(),
        description=r["description"], watching=watching,
        photos=[Photo(s3_key=p["s3_key"], url=file_url(p["s3_key"]), sort_order=p["sort_order"]) for p in photos],
        seller_contact=(Contact(email=r["seller_email"], phone=r["seller_phone"])
                        if viewer and r["seller_active"] else None),
        updated_at=r["updated_at"])


async def _editable_listing(conn: asyncpg.Connection, listing_id: UUID, user: CurrentUser) -> bool:
    """The seller or an admin may change a listing. Returns True when it's an admin editing someone else's."""
    seller_id = await conn.fetchval(
        "SELECT seller_id FROM listings WHERE id = $1 AND deleted_at IS NULL", listing_id)
    if seller_id is None:
        raise not_found("Listing")
    if seller_id == user.id:
        return False
    if not user.is_admin:
        raise forbidden("Only the seller can change this listing.")
    return True


async def _insert_photos(conn: asyncpg.Connection, listing_id: UUID, keys: list[str]) -> None:
    await conn.executemany(
        "INSERT INTO listing_photos (listing_id, s3_key, sort_order) VALUES ($1, $2, $3)",
        [(listing_id, key, i) for i, key in enumerate(keys, start=1)])


@router.get("", response_model=Page[ListingSummary], summary="Browse and search listings (guests allowed)")
async def list_listings(
    q: str | None = Query(None, max_length=200, description="Keyword search over title and description"),
    category_id: int | None = Query(None, ge=1, le=MAX_INT_ID),
    min_price: Decimal | None = Query(None, ge=0),
    max_price: Decimal | None = Query(None, ge=0),
    status: list[ListingStatus] | None = Query(None, description="Repeat to allow several, e.g. status=available&status=reserved"),
    seller_id: UUID | None = None,
    sort: ListingSort = Query("newest", description="newest, price_asc or price_desc"),
    page: PageParams = Depends(page_params),
    viewer: CurrentUser | None = Depends(optional_user),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        _SELECT + f"""
        WHERE l.deleted_at IS NULL
          AND ((l.hidden_by_strike_id IS NULL AND l.held_for_review_at IS NULL)
               OR (l.seller_id = $6 AND $6::uuid = $9::uuid))
          AND ($1::int IS NULL OR l.category_id = $1)
          AND ($2::numeric IS NULL OR l.price >= $2)
          AND ($3::numeric IS NULL OR l.price <= $3)
          AND ($4::text[] IS NULL OR l.status::text = ANY($4::text[]))
          AND ($5::text IS NULL OR numnode(websearch_to_tsquery('english', $5)) = 0
               OR l.search_vector @@ websearch_to_tsquery('english', $5))
          AND ($6::uuid IS NULL OR l.seller_id = $6)
        ORDER BY {_ORDER[sort]}
        LIMIT $7 OFFSET $8""",
        category_id, min_price, max_price, status, search_text(q), seller_id, page.limit + 1, page.offset,
        viewer.id if viewer else None)
    tags = await seller_trust_tags(conn, {r["seller_id"] for r in rows})
    return make_page(rows, page, lambda r: _summary(r, tags.get(r["seller_id"])))


@router.get("/{listing_id}", response_model=ListingDetail, summary="One listing with all photos")
async def get_listing(listing_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    return await _detail(conn, listing_id, viewer)


@router.post("", response_model=ListingDetail, status_code=201, summary="Create a listing")
async def create_listing(body: ListingCreate, background: BackgroundTasks, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    if await is_listing_suspended(conn, user.id):
        raise forbidden("Your ability to post listings is suspended pending moderator review "
                        "(seller trust score, future plan §1.5).")
    await verify_own_uploads(body.photo_keys, "listing_photo", user.id)
    async with conn.transaction():
        listing_id = await conn.fetchval(
            """INSERT INTO listings (seller_id, title, description, price, category_id, location, negotiable)
               VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id""",
            user.id, body.title, body.description, body.price, body.category_id, body.location, body.negotiable)
        await _insert_photos(conn, listing_id, body.photo_keys)
        # Automatic flagging (§1.6). A listing held as a possible prohibited item alerts nobody yet.
        held = await screen_text(conn, background, "listing", listing_id)
        pushes = [] if held else await listing_alerts(conn, listing_id)
    await mark_attached(body.photo_keys)
    push_alerts(background, pushes)
    if body.photo_keys:
        request_photo_screen(background, "listing", listing_id)
    return await _detail(conn, listing_id, user)


@router.patch("/{listing_id}", response_model=ListingDetail, summary="Edit a listing (seller or admin)")
async def update_listing(listing_id: UUID, body: ListingUpdate, background: BackgroundTasks,
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    by_admin = await _editable_listing(conn, listing_id, user)
    changes = body.model_dump(exclude_unset=True)
    for required in ("title", "price", "category_id"):
        if required in changes and changes[required] is None:
            raise HTTPException(422, f"{required} can't be empty.")
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        before = await conn.fetchrow(
            "SELECT title, price, negotiable FROM listings WHERE id = $1 FOR UPDATE", listing_id)
        await conn.execute(f"UPDATE listings SET {sql} WHERE id = $1", listing_id, *values)
        if by_admin:
            await log_moderation(conn, user.id, "edit_listing", "listing", listing_id)
        held = False
        if changes.keys() & {"title", "description"}:
            held = await screen_text(conn, background, "listing", listing_id)
        # A lower price or new words can match searches it didn't before.
        pushes = await listing_alerts(conn, listing_id) if changes.keys() - {"location"} and not held else []
        watchers = await _notify_watchers(conn, listing_id, before, changes)
    push_alerts(background, pushes)
    for user_ids, payload in watchers:
        background.add_task(deliver_push, user_ids, "listing_watch", payload)
    return await _detail(conn, listing_id, user)


def _rupees(price: Decimal) -> str:
    return f"₹{price:,.0f}"


async def _notify_watchers(conn: asyncpg.Connection, listing_id: UUID, before: asyncpg.Record,
                           changes: dict) -> list[tuple[list[UUID], dict]]:
    """Price watch (§2.3): tell watchers about a new price or the listing being marked negotiable."""
    new_price = changes.get("price", before["price"])
    price_changed = new_price != before["price"]
    now_negotiable = changes.get("negotiable") is True and not before["negotiable"]
    if not (price_changed or now_negotiable):
        return []
    row = await conn.fetchrow(
        "SELECT title, seller_id, status::text AS status, hidden_by_strike_id IS NULL AND held_for_review_at IS NULL "
        "AS visible FROM listings WHERE id = $1", listing_id)
    if row["status"] == "sold" or not row["visible"]:
        return []
    watchers = [r["user_id"] for r in await conn.fetch(
        "SELECT user_id FROM listing_watches WHERE listing_id = $1 AND user_id <> $2", listing_id, row["seller_id"])]
    if not watchers:
        return []
    title = row["title"]
    if price_changed:
        word = "Price drop" if new_price < before["price"] else "Price change"
        message = f'{word} on "{title}": {_rupees(before["price"])} → {_rupees(new_price)}'
        if now_negotiable:
            message += ", and it's now negotiable"
    else:
        message = f'"{title}" is now marked negotiable ({_rupees(new_price)})'
    payload = {"message": message, "listing_id": str(listing_id), "old_price": str(before["price"]),
               "price": str(new_price), "negotiable": bool(changes.get("negotiable", before["negotiable"]))}
    await create_notifications(conn, watchers, "listing_watch", payload)
    return [(watchers, payload)]


@router.patch("/{listing_id}/status", response_model=ListingDetail,
              summary="Mark available / reserved / sold (seller or admin, FR-5)")
async def update_status(listing_id: UUID, body: StatusUpdate, background: BackgroundTasks,
                        user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    by_admin = await _editable_listing(conn, listing_id, user)
    async with conn.transaction():
        await conn.execute("UPDATE listings SET status = $2 WHERE id = $1", listing_id, body.status)
        if by_admin:
            await log_moderation(conn, user.id, "change_listing_status", "listing", listing_id, body.status)
        # Back on sale (e.g. a reservation fell through): alert anyone not told yet.
        pushes = await listing_alerts(conn, listing_id) if body.status == "available" else []
    push_alerts(background, pushes)
    return await _detail(conn, listing_id, user)


@router.put("/{listing_id}/photos", response_model=ListingDetail,
            summary="Replace the photo list (add, remove or reorder; seller or admin)")
async def replace_photos(listing_id: UUID, body: PhotosUpdate, background: BackgroundTasks,
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    by_admin = await _editable_listing(conn, listing_id, user)
    old_keys = {r["s3_key"] for r in await conn.fetch(
        "SELECT s3_key FROM listing_photos WHERE listing_id = $1", listing_id)}
    new_keys = [k for k in body.photo_keys if k not in old_keys]
    await verify_own_uploads(new_keys, "listing_photo", user.id)
    async with conn.transaction():
        await conn.execute("DELETE FROM listing_photos WHERE listing_id = $1", listing_id)
        await _insert_photos(conn, listing_id, body.photo_keys)
        await conn.execute("UPDATE listings SET updated_at = now() WHERE id = $1", listing_id)
        if by_admin:
            await log_moderation(conn, user.id, "replace_listing_photos", "listing", listing_id)
    await mark_attached(new_keys)
    background.add_task(delete_objects, sorted(old_keys - set(body.photo_keys)))
    if new_keys:
        request_photo_screen(background, "listing", listing_id)
    return await _detail(conn, listing_id, user)


@router.delete("/{listing_id}", status_code=204,
               summary="Remove a listing (seller, Buy & Sell moderator or admin; FR-10)",
               description="A moderator removing a listing that has an open report counts as resolving "
                           "that report: the listing is hidden (the seller can appeal), the seller gets "
                           "a strike (`severity`, default non_severe; future plan §1.5) and is told why "
                           "(`reason`). Any other removal (by the seller, a moderator or an admin) is "
                           "permanent: the listing, its photos, watches and reports are deleted from the "
                           "database and storage. A moderator's removal tells the seller the reason.")
async def delete_listing(background: BackgroundTasks, listing_id: UUID,
                         reason: str | None = Query(None, max_length=500),
                         severity: Severity = Query("non_severe", description="Only used when a moderator "
                                                    "removes a reported listing"),
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(
        "SELECT seller_id, title FROM listings WHERE id = $1 AND deleted_at IS NULL", listing_id)
    if row is None:
        raise not_found("Listing")
    seller_id = row["seller_id"]
    is_owner = seller_id == user.id
    if not is_owner and not await is_module_moderator(conn, user, "buy_sell"):
        raise forbidden("Only the seller or a Buy & Sell moderator can remove this listing.")
    async with conn.transaction():
        report_id = None if is_owner else await conn.fetchval(
            """SELECT id FROM reports WHERE target_type = 'listing' AND target_id = $1 AND status = 'open'
               ORDER BY created_at LIMIT 1""", listing_id)
        if report_id is not None:
            # Same as resolving the report with remove_content: hide + strike (reversible on appeal).
            await close_reports(conn, "listing", [listing_id], user.id, reason)
            await conn.execute("UPDATE listings SET held_for_review_at = NULL WHERE id = $1", listing_id)
            await record_strike(conn, report_id=report_id, listing_id=listing_id, seller_id=seller_id,
                                listing_title=row["title"], severity=severity, moderator_id=user.id, note=reason)
        else:
            # Permanent: photos, watches and reports go with it (ON DELETE CASCADE); a strike or chat
            # about it keeps a copy of the title (migration 023).
            photo_keys = [r["s3_key"] for r in await conn.fetch(
                "SELECT s3_key FROM listing_photos WHERE listing_id = $1", listing_id)]
            await conn.execute("DELETE FROM listings WHERE id = $1", listing_id)
            background.add_task(delete_objects, photo_keys)
            if not is_owner:
                payload = {"message": f'A moderator removed your listing "{row["title"]}".'
                                      + (f" Reason: {reason}" if reason else ""),
                           "listing_id": str(listing_id)}
                await create_notifications(conn, [seller_id], "moderation_action", payload)
                background.add_task(deliver_push, [seller_id], "moderation_action", payload)
        if not is_owner:
            await log_moderation(conn, user.id, "remove_listing", "listing", listing_id, reason)
    return Response(status_code=204)


@router.put("/{listing_id}/watch", status_code=204,
            summary="Watch a listing: be told when its price changes or it's marked negotiable (§2.3)")
async def watch_listing(listing_id: UUID, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    r = await conn.fetchrow(
        "SELECT seller_id FROM listings WHERE id = $1 AND deleted_at IS NULL AND hidden_by_strike_id IS NULL "
        "AND held_for_review_at IS NULL", listing_id)
    if r is None:
        raise not_found("Listing")
    if r["seller_id"] == user.id:
        raise HTTPException(422, "You can't watch your own listing.")
    await conn.execute("INSERT INTO listing_watches (user_id, listing_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                       user.id, listing_id)
    return Response(status_code=204)


@router.delete("/{listing_id}/watch", status_code=204, summary="Stop watching a listing")
async def unwatch_listing(listing_id: UUID, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    await conn.execute("DELETE FROM listing_watches WHERE user_id = $1 AND listing_id = $2", user.id, listing_id)
    return Response(status_code=204)


watch_router = APIRouter(tags=["Buy & Sell"])


@watch_router.get("/me/watched-listings", response_model=Page[ListingSummary],
                  summary="Listings I'm watching for price changes, most recently watched first")
async def my_watched_listings(page: PageParams = Depends(page_params), user: CurrentUser = Depends(current_user),
                              conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(
        _SELECT + """ JOIN listing_watches w ON w.listing_id = l.id AND w.user_id = $1
        WHERE l.deleted_at IS NULL AND l.hidden_by_strike_id IS NULL AND l.held_for_review_at IS NULL
        ORDER BY w.created_at DESC LIMIT $2 OFFSET $3""", user.id, page.limit + 1, page.offset)
    tags = await seller_trust_tags(conn, {r["seller_id"] for r in rows})
    return make_page(rows, page, lambda r: _summary(r, tags.get(r["seller_id"])))
