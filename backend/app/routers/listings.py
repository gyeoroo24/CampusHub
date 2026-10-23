"""Buy & Sell listings (FR-4, FR-5, FR-6, FR-10)."""
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from pydantic import AfterValidator, BaseModel, Field

from ..auth import CurrentUser, current_user, optional_user
from ..common import (CategoryRef, Contact, Page, PageParams, Photo, UserRef, forbidden, make_page,
                      not_found, page_params, set_clause)
from ..db import get_conn
from ..permissions import is_module_moderator, log_moderation
from ..storage import delete_objects, file_url, verify_own_uploads

router = APIRouter(prefix="/listings", tags=["Buy & Sell"])

ListingStatus = Literal["available", "reserved", "sold"]
MAX_PHOTOS = 10


def _unique_keys(keys: list[str]) -> list[str]:
    if len(set(keys)) != len(keys):
        raise ValueError("photo_keys contains the same photo twice")
    return keys


PhotoKeys = Annotated[list[str], Field(max_length=MAX_PHOTOS), AfterValidator(_unique_keys)]


class ListingCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    description: str | None = Field(None, max_length=5000)
    price: Decimal = Field(ge=0, max_digits=10, decimal_places=2, description="Rupees")
    category_id: int
    location: str | None = Field(None, max_length=200)
    photo_keys: PhotoKeys = Field(default_factory=list,
                                  description="s3_key values from POST /uploads, in display order; first = cover")


class ListingUpdate(BaseModel):
    title: str | None = Field(None, min_length=1, max_length=120)
    description: str | None = Field(None, max_length=5000)
    price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2)
    category_id: int | None = None
    location: str | None = Field(None, max_length=200)


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
    cover_photo_url: str | None
    created_at: datetime


class ListingDetail(ListingSummary):
    description: str | None
    photos: list[Photo]
    seller_contact: Contact | None = Field(description="Shown to signed-in users only (scenario 1)")
    updated_at: datetime


_SELECT = """
SELECT l.id, l.title, l.description, l.price, l.status::text AS status, l.location,
       l.created_at, l.updated_at, l.seller_id,
       c.id AS category_id, c.name AS category_name,
       u.name AS seller_name, u.email::text AS seller_email, u.phone AS seller_phone,
       (SELECT p.s3_key FROM listing_photos p WHERE p.listing_id = l.id ORDER BY p.sort_order LIMIT 1) AS cover_key
FROM listings l
JOIN bs_categories c ON c.id = l.category_id
JOIN users u ON u.id = l.seller_id
"""


def _summary(r: asyncpg.Record) -> ListingSummary:
    return ListingSummary(
        id=r["id"], title=r["title"], price=r["price"], status=r["status"], location=r["location"],
        category=CategoryRef(id=r["category_id"], name=r["category_name"]),
        seller=UserRef(id=r["seller_id"], name=r["seller_name"]),
        cover_photo_url=file_url(r["cover_key"]) if r["cover_key"] else None,
        created_at=r["created_at"])


async def _detail(conn: asyncpg.Connection, listing_id: UUID, viewer: CurrentUser | None) -> ListingDetail:
    r = await conn.fetchrow(_SELECT + " WHERE l.id = $1 AND l.deleted_at IS NULL", listing_id)
    if r is None:
        raise not_found("Listing")
    photos = await conn.fetch(
        "SELECT s3_key, sort_order FROM listing_photos WHERE listing_id = $1 ORDER BY sort_order", listing_id)
    return ListingDetail(
        **_summary(r).model_dump(),
        description=r["description"],
        photos=[Photo(s3_key=p["s3_key"], url=file_url(p["s3_key"]), sort_order=p["sort_order"]) for p in photos],
        seller_contact=Contact(email=r["seller_email"], phone=r["seller_phone"]) if viewer else None,
        updated_at=r["updated_at"])


async def _owned_listing(conn: asyncpg.Connection, listing_id: UUID, user: CurrentUser) -> None:
    seller_id = await conn.fetchval(
        "SELECT seller_id FROM listings WHERE id = $1 AND deleted_at IS NULL", listing_id)
    if seller_id is None:
        raise not_found("Listing")
    if seller_id != user.id:
        raise forbidden("Only the seller can change this listing.")


async def _insert_photos(conn: asyncpg.Connection, listing_id: UUID, keys: list[str]) -> None:
    await conn.executemany(
        "INSERT INTO listing_photos (listing_id, s3_key, sort_order) VALUES ($1, $2, $3)",
        [(listing_id, key, i) for i, key in enumerate(keys, start=1)])


@router.get("", response_model=Page[ListingSummary], summary="Browse and search listings (guests allowed)")
async def list_listings(
    q: str | None = Query(None, max_length=200, description="Keyword search over title and description"),
    category_id: int | None = None,
    min_price: Decimal | None = Query(None, ge=0),
    max_price: Decimal | None = Query(None, ge=0),
    status: list[ListingStatus] | None = Query(None, description="Repeat to allow several, e.g. status=available&status=reserved"),
    seller_id: UUID | None = None,
    page: PageParams = Depends(page_params),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        _SELECT + """
        WHERE l.deleted_at IS NULL
          AND ($1::int IS NULL OR l.category_id = $1)
          AND ($2::numeric IS NULL OR l.price >= $2)
          AND ($3::numeric IS NULL OR l.price <= $3)
          AND ($4::text[] IS NULL OR l.status::text = ANY($4::text[]))
          AND ($5::text IS NULL OR l.search_vector @@ websearch_to_tsquery('english', $5))
          AND ($6::uuid IS NULL OR l.seller_id = $6)
        ORDER BY l.created_at DESC, l.id DESC
        LIMIT $7 OFFSET $8""",
        category_id, min_price, max_price, status, q, seller_id, page.limit + 1, page.offset)
    return make_page(rows, page, _summary)


@router.get("/{listing_id}", response_model=ListingDetail, summary="One listing with all photos")
async def get_listing(listing_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    return await _detail(conn, listing_id, viewer)


@router.post("", response_model=ListingDetail, status_code=201, summary="Create a listing")
async def create_listing(body: ListingCreate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    await verify_own_uploads(body.photo_keys, "listing_photo", user.id)
    async with conn.transaction():
        listing_id = await conn.fetchval(
            """INSERT INTO listings (seller_id, title, description, price, category_id, location)
               VALUES ($1, $2, $3, $4, $5, $6) RETURNING id""",
            user.id, body.title, body.description, body.price, body.category_id, body.location)
        await _insert_photos(conn, listing_id, body.photo_keys)
    return await _detail(conn, listing_id, user)


@router.patch("/{listing_id}", response_model=ListingDetail, summary="Edit a listing (seller only)")
async def update_listing(listing_id: UUID, body: ListingUpdate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    await _owned_listing(conn, listing_id, user)
    changes = body.model_dump(exclude_unset=True)
    for required in ("title", "price", "category_id"):
        if required in changes and changes[required] is None:
            changes.pop(required)
    sql, values = set_clause(changes, start=2)
    await conn.execute(f"UPDATE listings SET {sql} WHERE id = $1", listing_id, *values)
    return await _detail(conn, listing_id, user)


@router.patch("/{listing_id}/status", response_model=ListingDetail,
              summary="Mark available / reserved / sold (seller only, FR-5)")
async def update_status(listing_id: UUID, body: StatusUpdate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    await _owned_listing(conn, listing_id, user)
    await conn.execute("UPDATE listings SET status = $2 WHERE id = $1", listing_id, body.status)
    return await _detail(conn, listing_id, user)


@router.put("/{listing_id}/photos", response_model=ListingDetail,
            summary="Replace the photo list (add, remove or reorder; seller only)")
async def replace_photos(listing_id: UUID, body: PhotosUpdate, background: BackgroundTasks,
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    await _owned_listing(conn, listing_id, user)
    old_keys = {r["s3_key"] for r in await conn.fetch(
        "SELECT s3_key FROM listing_photos WHERE listing_id = $1", listing_id)}
    await verify_own_uploads([k for k in body.photo_keys if k not in old_keys], "listing_photo", user.id)
    async with conn.transaction():
        await conn.execute("DELETE FROM listing_photos WHERE listing_id = $1", listing_id)
        await _insert_photos(conn, listing_id, body.photo_keys)
        await conn.execute("UPDATE listings SET updated_at = now() WHERE id = $1", listing_id)
    background.add_task(delete_objects, sorted(old_keys - set(body.photo_keys)))
    return await _detail(conn, listing_id, user)


@router.delete("/{listing_id}", status_code=204,
               summary="Remove a listing (seller, Buy & Sell moderator or admin; FR-10)")
async def delete_listing(listing_id: UUID, reason: str | None = Query(None, max_length=500),
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    seller_id = await conn.fetchval(
        "SELECT seller_id FROM listings WHERE id = $1 AND deleted_at IS NULL", listing_id)
    if seller_id is None:
        raise not_found("Listing")
    is_owner = seller_id == user.id
    if not is_owner and not await is_module_moderator(conn, user, "buy_sell"):
        raise forbidden("Only the seller or a Buy & Sell moderator can remove this listing.")
    async with conn.transaction():
        await conn.execute("UPDATE listings SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                           listing_id, user.id)
        if not is_owner:
            await log_moderation(conn, user.id, "remove_listing", "listing", listing_id, reason)
    return Response(status_code=204)
