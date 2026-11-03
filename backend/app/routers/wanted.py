"""Wanted posts ("Taking it further", rev 6): buyers say what they need instead of waiting for it.

  "Need a cycle, budget ₹3,000" in category Cycles.

The author is alerted when a matching listing appears (same category, within budget, shares a
word with the title; app/alerts.py), and sees the listings that already match when posting.
Ownership and moderation work like listings: the author or an admin edits, the author, a Buy &
Sell moderator or an admin removes, and anyone signed in can report a post.
"""
from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field

from ..alerts import LISTING_MATCHES_WANTED
from ..auth import CurrentUser, current_user, optional_user
from ..common import (MAX_INT_ID, CategoryId, CategoryRef, Contact, Page, PageParams, UserRef, forbidden, make_page,
                      not_found, page_params, search_text, set_clause, text)
from ..db import get_conn
from ..permissions import is_module_moderator, log_moderation
from .listings import _SELECT as LISTING_SELECT
from .listings import ListingSummary
from .listings import _summary as listing_summary

router = APIRouter(prefix="/wanted", tags=["Wanted posts"])

WantedStatus = Literal["open", "fulfilled", "closed"]
MAX_OPEN_POSTS = 10


class WantedCreate(BaseModel):
    title: text(120) = Field(examples=["Need a cycle for campus"])
    description: text(2000, min_length=0) | None = None
    category_id: CategoryId
    max_price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2,
                                      description="Budget in rupees; leave out for 'open to offers'")


class WantedUpdate(BaseModel):
    title: text(120) | None = None
    description: text(2000, min_length=0) | None = None
    category_id: CategoryId | None = None
    max_price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2)


class StatusUpdate(BaseModel):
    status: WantedStatus = Field(description="fulfilled = got it; closed = no longer needed")


class WantedSummary(BaseModel):
    id: UUID
    title: str
    category: CategoryRef
    max_price: Decimal | None
    status: WantedStatus
    author: UserRef
    created_at: datetime


class WantedDetail(WantedSummary):
    description: str | None
    author_contact: Contact | None = Field(description="Shown to signed-in users only")
    updated_at: datetime
    possible_matches: list[ListingSummary] | None = Field(
        None, description="Only on create: available listings that already match")


_SELECT = """
SELECT w.id, w.title, w.description, w.max_price, w.status::text AS status, w.created_at, w.updated_at,
       w.author_id, c.id AS category_id, c.name AS category_name,
       u.name AS author_name, u.email::text AS author_email, u.phone AS author_phone, u.is_active AS author_active
FROM wanted_posts w
JOIN bs_categories c ON c.id = w.category_id
JOIN users u ON u.id = w.author_id
"""


def _summary(r: asyncpg.Record) -> WantedSummary:
    return WantedSummary(id=r["id"], title=r["title"], max_price=r["max_price"], status=r["status"],
                         category=CategoryRef(id=r["category_id"], name=r["category_name"]),
                         author=UserRef(id=r["author_id"], name=r["author_name"]), created_at=r["created_at"])


async def _detail(conn: asyncpg.Connection, post_id: UUID, viewer: CurrentUser | None) -> WantedDetail:
    r = await conn.fetchrow(_SELECT + " WHERE w.id = $1 AND w.deleted_at IS NULL", post_id)
    if r is None:
        raise not_found("Wanted post")
    return WantedDetail(**_summary(r).model_dump(), description=r["description"], updated_at=r["updated_at"],
                        author_contact=(Contact(email=r["author_email"], phone=r["author_phone"])
                                        if viewer and r["author_active"] else None))


async def _matches(conn: asyncpg.Connection, post_id: UUID) -> list[ListingSummary]:
    """Available listings by other people that match the post, best match first. Removed, hidden and
    held-for-review listings never show."""
    rows = await conn.fetch(
        LISTING_SELECT + f"""
        JOIN wanted_posts w ON w.id = $1
        WHERE l.deleted_at IS NULL AND l.status = 'available' AND l.seller_id <> w.author_id
          -- never surface what moderators hid or automatic flagging is holding back
          AND l.hidden_by_strike_id IS NULL AND l.held_for_review_at IS NULL
          AND {LISTING_MATCHES_WANTED}
        ORDER BY ts_rank(l.search_vector,
                         replace(plainto_tsquery('english', w.title)::text, ' & ', ' | ')::tsquery) DESC,
                 l.created_at DESC
        LIMIT 10""", post_id)
    return [listing_summary(r) for r in rows]


async def _editable(conn: asyncpg.Connection, post_id: UUID, user: CurrentUser) -> bool:
    """The author or an admin may change a post. Returns True when it's an admin editing someone else's."""
    author_id = await conn.fetchval("SELECT author_id FROM wanted_posts WHERE id = $1 AND deleted_at IS NULL", post_id)
    if author_id is None:
        raise not_found("Wanted post")
    if author_id == user.id:
        return False
    if not user.is_admin:
        raise forbidden("Only the author can change this post.")
    return True


@router.get("", response_model=Page[WantedSummary], summary="Browse Wanted posts, newest first (guests allowed)")
async def list_wanted(
    q: str | None = Query(None, max_length=200, description="Keyword search over title and description"),
    category_id: int | None = Query(None, ge=1, le=MAX_INT_ID),
    status: list[WantedStatus] | None = Query(["open"], description="Default: open posts only. Repeat to allow several"),
    author_id: UUID | None = None,
    page: PageParams = Depends(page_params),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        _SELECT + """
        WHERE w.deleted_at IS NULL
          AND ($1::int IS NULL OR w.category_id = $1)
          AND ($2::text[] IS NULL OR w.status::text = ANY($2::text[]))
          AND ($3::text IS NULL OR numnode(websearch_to_tsquery('english', $3)) = 0
               OR w.search_vector @@ websearch_to_tsquery('english', $3))
          AND ($4::uuid IS NULL OR w.author_id = $4)
        ORDER BY w.created_at DESC, w.id DESC
        LIMIT $5 OFFSET $6""",
        category_id, status, search_text(q), author_id, page.limit + 1, page.offset)
    return make_page(rows, page, _summary)


@router.get("/{post_id}", response_model=WantedDetail, summary="One Wanted post")
async def get_wanted(post_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    return await _detail(conn, post_id, viewer)


@router.get("/{post_id}/matches", response_model=list[ListingSummary],
            summary="Available listings that match this post, best first (up to 10)")
async def wanted_matches(post_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM wanted_posts WHERE id = $1 AND deleted_at IS NULL)",
                               post_id):
        raise not_found("Wanted post")
    return await _matches(conn, post_id)


@router.post("", response_model=WantedDetail, status_code=201, summary="Post what you're looking for")
async def create_wanted(body: WantedCreate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM bs_categories WHERE id = $1)", body.category_id):
        raise HTTPException(422, "category_id isn't a Buy & Sell category.")
    async with conn.transaction():
        await conn.execute("SELECT 1 FROM users WHERE id = $1 FOR UPDATE", user.id)
        open_posts = await conn.fetchval(
            "SELECT count(*) FROM wanted_posts WHERE author_id = $1 AND status = 'open' AND deleted_at IS NULL",
            user.id)
        if open_posts >= MAX_OPEN_POSTS:
            raise HTTPException(409, f"You can have up to {MAX_OPEN_POSTS} open Wanted posts. Close one first.")
        post_id = await conn.fetchval(
            """INSERT INTO wanted_posts (author_id, title, description, category_id, max_price)
               VALUES ($1, $2, $3, $4, $5) RETURNING id""",
            user.id, body.title, body.description, body.category_id, body.max_price)
    result = await _detail(conn, post_id, user)
    result.possible_matches = await _matches(conn, post_id)
    return result


@router.patch("/{post_id}", response_model=WantedDetail, summary="Edit a Wanted post (author or admin)")
async def update_wanted(post_id: UUID, body: WantedUpdate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    by_admin = await _editable(conn, post_id, user)
    changes = body.model_dump(exclude_unset=True)
    for required in ("title", "category_id"):
        if required in changes and changes[required] is None:
            raise HTTPException(422, f"{required} can't be empty.")
    if changes.get("category_id") is not None and not await conn.fetchval(
            "SELECT EXISTS (SELECT 1 FROM bs_categories WHERE id = $1)", changes["category_id"]):
        raise HTTPException(422, "category_id isn't a Buy & Sell category.")
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        await conn.execute(f"UPDATE wanted_posts SET {sql} WHERE id = $1", post_id, *values)
        if by_admin:
            await log_moderation(conn, user.id, "edit_wanted_post", "wanted_post", post_id)
    return await _detail(conn, post_id, user)


@router.patch("/{post_id}/status", response_model=WantedDetail,
              summary="Mark open / fulfilled / closed (author or admin)")
async def update_status(post_id: UUID, body: StatusUpdate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    by_admin = await _editable(conn, post_id, user)
    async with conn.transaction():
        await conn.execute("UPDATE wanted_posts SET status = $2 WHERE id = $1", post_id, body.status)
        if by_admin:
            await log_moderation(conn, user.id, "change_wanted_post_status", "wanted_post", post_id, body.status)
    return await _detail(conn, post_id, user)


@router.delete("/{post_id}", status_code=204, summary="Remove a Wanted post (author, Buy & Sell moderator or admin)")
async def delete_wanted(post_id: UUID, reason: str | None = Query(None, max_length=500),
                        user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    author_id = await conn.fetchval("SELECT author_id FROM wanted_posts WHERE id = $1 AND deleted_at IS NULL", post_id)
    if author_id is None:
        raise not_found("Wanted post")
    is_owner = author_id == user.id
    if not is_owner and not await is_module_moderator(conn, user, "buy_sell"):
        raise forbidden("Only the author or a Buy & Sell moderator can remove this post.")
    async with conn.transaction():
        # Permanent: its reports go with it (ON DELETE CASCADE).
        await conn.execute("DELETE FROM wanted_posts WHERE id = $1", post_id)
        if not is_owner:
            await log_moderation(conn, user.id, "remove_wanted_post", "wanted_post", post_id, reason)
    return Response(status_code=204)
