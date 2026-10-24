"""Buy & Sell and Lost & Found categories. Users can add a missing one ("Others").

Names are matched ignoring case and extra spaces (categories.name_key), so adding
"  earbuds " when "Earbuds" exists returns the existing category instead of a duplicate.
"""
import asyncpg
from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel

from ..auth import CurrentUser, current_user
from ..common import CategoryRef, text
from ..db import get_conn

router = APIRouter(tags=["Categories"])


class CategoryCreate(BaseModel):
    name: text(50)


def _register(path: str, table: str, tag: str) -> None:
    @router.get(path, response_model=list[CategoryRef], tags=[tag], summary="List categories")
    async def list_categories(conn: asyncpg.Connection = Depends(get_conn)):
        rows = await conn.fetch(f"SELECT id, name FROM {table} ORDER BY name_key")
        return [CategoryRef(**dict(r)) for r in rows]

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


_register("/buy-sell/categories", "bs_categories", "Buy & Sell")
_register("/lost-found/categories", "lf_categories", "Lost & Found")
