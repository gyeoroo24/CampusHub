"""Saved searches and alerts ("Taking it further", rev 6).

"Tell me when a cycle under ₹3,000 appears", or "when someone finds an ID card". A saved
search keeps the filters of a Buy & Sell or Found-items search. Each new matching item sends
the owner a saved_search_match notification (matching lives in app/alerts.py), so nobody has
to keep refreshing. new_count is the "N new" badge: matching items posted since the owner
last opened the search (POST .../seen resets it).

To run a saved search, the app calls GET /listings or GET /found-reports with the search's
filters: they mean the same thing there.
"""
from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, model_validator

from ..alerts import FOUND_MATCHES_SEARCH, LISTING_MATCHES_SEARCH
from ..auth import CurrentUser, current_user
from ..common import CategoryId, not_found, text
from ..db import get_conn

router = APIRouter(prefix="/me/saved-searches", tags=["Saved searches"])

MAX_SAVED_SEARCHES = 20
Module = Literal["buy_sell", "lost_found"]


class SavedSearchCreate(BaseModel):
    module: Module = Field(description="buy_sell watches new listings; lost_found watches new found reports")
    name: text(80, single_line=True) = Field(examples=["Cycle under ₹3,000"])
    q: text(200, min_length=0) | None = Field(None, description="Keywords, as in the search box")
    category_id: CategoryId | None = Field(None, description="A Buy & Sell or Lost & Found category, by module")
    min_price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2, description="buy_sell only")
    max_price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2, description="buy_sell only")
    alerts_enabled: bool = True

    @model_validator(mode="after")
    def _check(self):
        self.q = self.q or None   # an empty search box means "any"
        if self.q is None and self.category_id is None and self.min_price is None and self.max_price is None:
            # A search with no keyword or filter matches every new post (e.g. "Drugs" alerting a
            # search named "hero cycle" that was saved with an empty search box).
            raise ValueError("Add keywords, a category or a price range: otherwise every new post would match")
        if self.module == "lost_found" and (self.min_price is not None or self.max_price is not None):
            raise ValueError("Lost & Found searches have no price filter")
        if self.min_price is not None and self.max_price is not None and self.min_price > self.max_price:
            raise ValueError("min_price can't be more than max_price")
        return self


class SavedSearchUpdate(BaseModel):
    """Send only what changes. The module can't change; send null to clear a filter."""
    name: text(80, single_line=True) | None = None
    q: text(200, min_length=0) | None = None
    category_id: CategoryId | None = None
    min_price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2)
    max_price: Decimal | None = Field(None, ge=0, max_digits=10, decimal_places=2)
    alerts_enabled: bool | None = None


class SavedSearch(BaseModel):
    id: UUID
    module: Module
    name: str
    q: str | None
    category_id: int | None
    category_name: str | None
    min_price: Decimal | None
    max_price: Decimal | None
    alerts_enabled: bool
    new_count: int = Field(description="Matching items posted since last_seen_at (excluding your own)")
    last_seen_at: datetime
    created_at: datetime
    updated_at: datetime


_SELECT = f"""
SELECT s.id, s.module::text AS module, s.name, s.query, s.min_price, s.max_price, s.alerts_enabled,
       s.last_seen_at, s.created_at, s.updated_at,
       coalesce(s.bs_category_id, s.lf_category_id) AS category_id, coalesce(bc.name, lc.name) AS category_name,
       CASE s.module
         WHEN 'buy_sell' THEN (SELECT count(*) FROM listings l
                               WHERE l.deleted_at IS NULL AND l.status = 'available' AND l.seller_id <> s.user_id
                                 AND l.created_at > s.last_seen_at AND {LISTING_MATCHES_SEARCH})
         ELSE (SELECT count(*) FROM found_reports f
               WHERE f.deleted_at IS NULL AND f.status = 'open' AND f.reporter_id <> s.user_id
                 AND f.created_at > s.last_seen_at AND {FOUND_MATCHES_SEARCH})
       END AS new_count
FROM saved_searches s
LEFT JOIN bs_categories bc ON bc.id = s.bs_category_id
LEFT JOIN lf_categories lc ON lc.id = s.lf_category_id
"""


def _saved(r: asyncpg.Record) -> SavedSearch:
    return SavedSearch(id=r["id"], module=r["module"], name=r["name"], q=r["query"], category_id=r["category_id"],
                       category_name=r["category_name"], min_price=r["min_price"], max_price=r["max_price"],
                       alerts_enabled=r["alerts_enabled"], new_count=r["new_count"], last_seen_at=r["last_seen_at"],
                       created_at=r["created_at"], updated_at=r["updated_at"])


async def _get(conn: asyncpg.Connection, search_id: UUID, user: CurrentUser) -> SavedSearch:
    r = await conn.fetchrow(_SELECT + " WHERE s.id = $1 AND s.user_id = $2", search_id, user.id)
    if r is None:
        raise not_found("Saved search")
    return _saved(r)


async def _check_category(conn: asyncpg.Connection, module: str, category_id: int | None) -> None:
    if category_id is None:
        return
    table = "bs_categories" if module == "buy_sell" else "lf_categories"
    if not await conn.fetchval(f"SELECT EXISTS (SELECT 1 FROM {table} WHERE id = $1)", category_id):
        raise HTTPException(422, "category_id isn't a category of this module.")


@router.get("", response_model=list[SavedSearch], summary="My saved searches, oldest first, with new-item counts")
async def list_saved_searches(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(_SELECT + " WHERE s.user_id = $1 ORDER BY s.created_at, s.id", user.id)
    return [_saved(r) for r in rows]


@router.post("", response_model=SavedSearch, status_code=201, summary="Save a search and get alerts for new matches")
async def create_saved_search(body: SavedSearchCreate, user: CurrentUser = Depends(current_user),
                              conn: asyncpg.Connection = Depends(get_conn)):
    await _check_category(conn, body.module, body.category_id)
    async with conn.transaction():
        # Lock the user's row so two parallel requests can't both pass the limit.
        await conn.execute("SELECT 1 FROM users WHERE id = $1 FOR UPDATE", user.id)
        if await conn.fetchval("SELECT count(*) FROM saved_searches WHERE user_id = $1", user.id) >= MAX_SAVED_SEARCHES:
            raise HTTPException(409, f"You can keep up to {MAX_SAVED_SEARCHES} saved searches. Delete one first.")
        search_id = await conn.fetchval(
            """INSERT INTO saved_searches (user_id, module, name, query, bs_category_id, lf_category_id,
                                           min_price, max_price, alerts_enabled)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id""",
            user.id, body.module, body.name, body.q,
            body.category_id if body.module == "buy_sell" else None,
            body.category_id if body.module == "lost_found" else None,
            body.min_price, body.max_price, body.alerts_enabled)
    return await _get(conn, search_id, user)


@router.patch("/{search_id}", response_model=SavedSearch, summary="Edit a saved search, or turn its alerts on or off")
async def update_saved_search(search_id: UUID, body: SavedSearchUpdate, user: CurrentUser = Depends(current_user),
                              conn: asyncpg.Connection = Depends(get_conn)):
    current = await _get(conn, search_id, user)
    changes = body.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(422, "Send at least one field to change.")
    for required in ("name", "alerts_enabled"):
        if required in changes and changes[required] is None:
            raise HTTPException(422, f"{required} can't be empty.")
    if current.module == "lost_found" and (changes.get("min_price") is not None or changes.get("max_price") is not None):
        raise HTTPException(422, "Lost & Found searches have no price filter.")
    low = changes.get("min_price", current.min_price)
    high = changes.get("max_price", current.max_price)
    if low is not None and high is not None and low > high:
        raise HTTPException(422, "min_price can't be more than max_price.")
    after = {"q": current.q, "category_id": current.category_id,
             "min_price": current.min_price, "max_price": current.max_price} | changes
    if not (after["q"] or after["category_id"] is not None or after["min_price"] is not None
            or after["max_price"] is not None):
        raise HTTPException(422, "Keep keywords, a category or a price range: otherwise every new post would match.")
    if "category_id" in changes:
        await _check_category(conn, current.module, changes["category_id"])
        changes["bs_category_id" if current.module == "buy_sell" else "lf_category_id"] = changes.pop("category_id")
    if "q" in changes:
        changes["query"] = changes.pop("q") or None
    cols = list(changes)
    sql = ", ".join(f"{c} = ${i}" for i, c in enumerate(cols, start=3))
    await conn.execute(f"UPDATE saved_searches SET {sql} WHERE id = $1 AND user_id = $2",
                       search_id, user.id, *(changes[c] for c in cols))
    return await _get(conn, search_id, user)


@router.post("/{search_id}/seen", response_model=SavedSearch,
             summary="I've looked at the results: reset new_count to 0")
async def mark_seen(search_id: UUID, user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    updated = await conn.execute("UPDATE saved_searches SET last_seen_at = now() WHERE id = $1 AND user_id = $2",
                                 search_id, user.id)
    if updated.endswith(" 0"):
        raise not_found("Saved search")
    return await _get(conn, search_id, user)


@router.delete("/{search_id}", status_code=204, summary="Delete a saved search (its alerts stop)")
async def delete_saved_search(search_id: UUID, user: CurrentUser = Depends(current_user),
                              conn: asyncpg.Connection = Depends(get_conn)):
    deleted = await conn.execute("DELETE FROM saved_searches WHERE id = $1 AND user_id = $2", search_id, user.id)
    if deleted.endswith(" 0"):
        raise not_found("Saved search")
    return Response(status_code=204)
