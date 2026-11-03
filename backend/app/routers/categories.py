"""Buy & Sell and Lost & Found categories. Users can add a missing one ("Others"); that module's
moderators (and the admin) can delete one, moving whatever used it to another category.

Names are matched ignoring case and extra spaces (categories.name_key), so adding
"  earbuds " when "Earbuds" exists returns the existing category instead of a duplicate.
"""
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel

from ..auth import CurrentUser, current_user
from ..categories_suggest import suggest_category
from ..common import MAX_INT_ID, CategoryRef, forbidden, not_found, text
from ..db import get_conn
from ..permissions import is_module_moderator, log_moderation

router = APIRouter(tags=["Categories"])


class CategoryCreate(BaseModel):
    name: text(50)


class CategorySuggestion(BaseModel):
    category: CategoryRef | None = None


def _register(path: str, table: str, tag: str, module: str) -> None:
    users_of = _USERS[table]

    @router.get(path, response_model=list[CategoryRef], tags=[tag], summary="List categories")
    async def list_categories(conn: asyncpg.Connection = Depends(get_conn)):
        rows = await conn.fetch(f"SELECT id, name FROM {table} ORDER BY name_key")
        return [CategoryRef(**dict(r)) for r in rows]

    @router.get(path + "/suggest", response_model=CategorySuggestion, tags=[tag],
                summary="Suggest the closest existing category for a title",
                description="Nearest-neighbor lookup only (future plan §2.4) - never invents a new "
                            "category. `category` is null if nothing existing is a good enough fit, "
                            "or if the matching models aren't available in this environment.")
    async def suggest(title: str = Query(..., min_length=1, max_length=200),
                      conn: asyncpg.Connection = Depends(get_conn)):
        result = await suggest_category(conn, table, title)
        if result is None:
            return CategorySuggestion()
        cat_id, name = result
        return CategorySuggestion(category=CategoryRef(id=cat_id, name=name))

    @router.post(path, response_model=CategoryRef, status_code=201, tags=[tag],
                 summary="Add a category, or get the existing one with the same name",
                 responses={200: {"description": "A category with this name already existed"}})
    async def add_category(body: CategoryCreate, response: Response, user: CurrentUser = Depends(current_user),
                           conn: asyncpg.Connection = Depends(get_conn)):
        row = await conn.fetchrow(
            f"INSERT INTO {table} (name, created_by) VALUES (btrim($1), $2) "
            "ON CONFLICT (name_key) DO NOTHING RETURNING id, name", body.name, user.id)
        if row is None:
            response.status_code = 200
            row = await conn.fetchrow(
                f"SELECT id, name FROM {table} WHERE name_key = lower(regexp_replace(btrim($1), '\\s+', ' ', 'g'))",
                body.name)
        return CategoryRef(**dict(row))


    @router.delete(path + "/{category_id}", status_code=204, tags=[tag],
                   summary=f"Delete a category ({tag} moderator or admin)",
                   description="If anything uses the category (posts, including removed ones, or saved "
                               "searches), pass `move_to`: they are moved to that category first. "
                               "Without it the answer is 409 with how many items use it.")
    async def delete_category(category_id: int, move_to: int | None = Query(None, ge=1, le=MAX_INT_ID),
                              user: CurrentUser = Depends(current_user),
                              conn: asyncpg.Connection = Depends(get_conn)):
        if not await is_module_moderator(conn, user, module):
            raise forbidden(f"Only a {tag} moderator or the admin can delete categories.")
        name = await conn.fetchval(f"SELECT name FROM {table} WHERE id = $1", category_id)
        if name is None:
            raise not_found("Category")
        if move_to is not None:
            if move_to == category_id:
                raise HTTPException(422, "Pick a different category to move its items to.")
            if not await conn.fetchval(f"SELECT EXISTS (SELECT 1 FROM {table} WHERE id = $1)", move_to):
                raise not_found("Category to move items to")
        async with conn.transaction():
            await conn.execute(f"SELECT 1 FROM {table} WHERE id = $1 FOR UPDATE", category_id)
            in_use = {label: await conn.fetchval(f"SELECT count(*) FROM {t} WHERE {col} = $1", category_id)
                      for label, t, col in users_of}
            if any(in_use.values()) and move_to is None:
                used = ", ".join(f"{n} {label}" for label, n in in_use.items() if n)
                raise HTTPException(409, f"“{name}” is used by {used}. Choose a category to move them to.")
            for _, t, col in users_of:
                await conn.execute(f"UPDATE {t} SET {col} = $2 WHERE {col} = $1", category_id, move_to)
            await conn.execute(f"DELETE FROM {table} WHERE id = $1", category_id)
            # moderation_log.target_id is a UUID; category ids are ints, stored as UUID(int=id).
            await log_moderation(conn, user.id, "delete_category", table[:-1], UUID(int=category_id),
                                 f"{name} (id {category_id})" + (f", items moved to id {move_to}" if move_to else ""))
        return Response(status_code=204)


# What uses each table's categories: (label for the 409 message, table, column)
_USERS = {
    "bs_categories": [("listings", "listings", "category_id"), ("Wanted posts", "wanted_posts", "category_id"),
                      ("saved searches", "saved_searches", "bs_category_id")],
    "lf_categories": [("lost reports", "lost_reports", "category_id"), ("found reports", "found_reports", "category_id"),
                      ("saved searches", "saved_searches", "lf_category_id")],
}

_register("/buy-sell/categories", "bs_categories", "Buy & Sell", "buy_sell")
_register("/lost-found/categories", "lf_categories", "Lost & Found", "lost_found")
