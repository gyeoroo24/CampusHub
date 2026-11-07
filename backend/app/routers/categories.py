"""Buy & Sell and Lost & Found categories. Users can add a missing one ("Others"); that module's
moderators (and the admin) can delete one, moving whatever used it to another category, or deleting its
posts with it.

Names are matched ignoring case and extra spaces (categories.name_key), so adding
"  earbuds " when "Earbuds" exists returns the existing category instead of a duplicate.
"""
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel

from ..auth import CurrentUser, current_user
from ..categories_suggest import suggest_category
from ..common import MAX_INT_ID, CategoryRef, forbidden, not_found, text
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import close_reports, is_module_moderator, log_moderation
from ..storage import delete_objects

router = APIRouter(tags=["Categories"])


class CategoryCreate(BaseModel):
    name: text(50, single_line=True)


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
                               "searches), pass `move_to` to move them to that category first, or "
                               "`delete_posts=true` to delete its posts with it (their owners are told; saved "
                               "searches for it are deleted). With neither the answer is 409 with how many "
                               "items use it.")
    async def delete_category(background: BackgroundTasks, category_id: int,
                              move_to: int | None = Query(None, ge=1, le=MAX_INT_ID),
                              delete_posts: bool = Query(False),
                              user: CurrentUser = Depends(current_user),
                              conn: asyncpg.Connection = Depends(get_conn)):
        if not await is_module_moderator(conn, user, module):
            raise forbidden(f"Only a {tag} moderator or the admin can delete categories.")
        name = await conn.fetchval(f"SELECT name FROM {table} WHERE id = $1", category_id)
        if name is None:
            raise not_found("Category")
        if move_to is not None and delete_posts:
            raise HTTPException(422, "Either move its posts to another category or delete them, not both.")
        if move_to is not None:
            if move_to == category_id:
                raise HTTPException(422, "Pick a different category to move its items to.")
            if not await conn.fetchval(f"SELECT EXISTS (SELECT 1 FROM {table} WHERE id = $1)", move_to):
                raise not_found("Category to move items to")
        notified: list = []
        payload: dict = {}
        async with conn.transaction():
            await conn.execute(f"SELECT 1 FROM {table} WHERE id = $1 FOR UPDATE", category_id)
            in_use = {label: await conn.fetchval(f"SELECT count(*) FROM {t} WHERE {col} = $1", category_id)
                      for label, t, col in users_of}
            if any(in_use.values()) and move_to is None and not delete_posts:
                used = ", ".join(f"{n} {label}" for label, n in in_use.items() if n)
                raise HTTPException(409, f"“{name}” is used by {used}. Choose a category to move them to, "
                                         "or delete its posts with it.")
            if delete_posts:
                owners, photo_keys = await _delete_posts(conn, table, category_id, user.id)
                notified = [o for o in owners if o != user.id]
                payload = {"message": f"A moderator deleted the {tag} category “{name}” and removed your posts in it.",
                           "kind": "category_deleted"}
                await create_notifications(conn, notified, "moderation_action", payload)
                background.add_task(delete_objects, photo_keys)
            else:
                for _, t, col in users_of:
                    await conn.execute(f"UPDATE {t} SET {col} = $2 WHERE {col} = $1", category_id, move_to)
            await conn.execute(f"DELETE FROM {table} WHERE id = $1", category_id)
            # moderation_log.target_id is a UUID; category ids are ints, stored as UUID(int=id).
            detail = (f", items moved to id {move_to}" if move_to else "") + \
                     (", its posts deleted (" + ", ".join(f"{n} {label}" for label, n in in_use.items() if n) + ")"
                      if delete_posts and any(in_use.values()) else "")
            await log_moderation(conn, user.id, "delete_category", table[:-1], UUID(int=category_id),
                                 f"{name} (id {category_id}){detail}")
        if notified:
            background.add_task(deliver_push, notified, "moderation_action", payload)
        return Response(status_code=204)


async def _delete_posts(conn: asyncpg.Connection, table: str, category_id: int, moderator_id: UUID):
    """Removes every post in the category the way that module removes a post, plus saved searches for it.
    Buy & Sell posts are deleted outright (their photos, watches and reports go with them). Lost & Found
    reports are removed (deleted_at) and their open reports closed; the removed rows lose their category.
    Returns (the posts' owners, photo keys to delete from storage)."""
    owners: set = set()
    keys: list[str] = []
    if table == "bs_categories":
        await _close_out_reports(conn, category_id, moderator_id)
        keys = [r["s3_key"] for r in await conn.fetch(
            """SELECT p.s3_key FROM listing_photos p JOIN listings l ON l.id = p.listing_id
               WHERE l.category_id = $1""", category_id)]
        deleted = await conn.fetch("DELETE FROM listings WHERE category_id = $1 RETURNING id, seller_id", category_id)
        owners |= {r["seller_id"] for r in deleted}
        # bookmarks.target_id has no foreign key (it can be a listing or an event), so clear it here.
        await conn.execute("DELETE FROM bookmarks WHERE target_type = 'listing' AND target_id = ANY($1::uuid[])",
                           [r["id"] for r in deleted])
        owners |= {r["author_id"] for r in await conn.fetch(
            "DELETE FROM wanted_posts WHERE category_id = $1 RETURNING author_id", category_id)}
        await conn.execute("DELETE FROM saved_searches WHERE bs_category_id = $1", category_id)
    else:
        for kind in ("lost", "found"):
            removed = await conn.fetch(
                f"""UPDATE {kind}_reports SET deleted_at = now(), deleted_by = $2
                    WHERE category_id = $1 AND deleted_at IS NULL RETURNING id, reporter_id""",
                category_id, moderator_id)
            owners |= {r["reporter_id"] for r in removed}
            keys += [r["s3_key"] for r in await conn.fetch(
                f"DELETE FROM {kind}_report_photos WHERE {kind}_report_id = ANY($1::uuid[]) RETURNING s3_key",
                [r["id"] for r in removed])]
            await close_reports(conn, f"{kind}_report", [r["id"] for r in removed], moderator_id,
                                "Removed with its category")
            await conn.execute(f"UPDATE {kind}_reports SET category_id = NULL WHERE category_id = $1", category_id)
        await conn.execute("DELETE FROM saved_searches WHERE lf_category_id = $1", category_id)
    return owners, keys


async def _close_out_reports(conn: asyncpg.Connection, category_id: int, moderator_id: UUID) -> None:
    """Buy & Sell posts are deleted outright, and their reports go with them (ON DELETE CASCADE). Before that
    happens, keep a moderation-log entry for every reported post and tell whoever filed an open report that
    the post was removed - the same outcome Lost & Found records by closing its reports."""
    reported = await conn.fetch(
        """SELECT r.target_type::text AS target_type, r.target_id,
                  coalesce(l.title, w.title) AS title,
                  count(*) AS reports,
                  array_agg(DISTINCT r.reporter_id) FILTER (WHERE r.status = 'open' AND r.reporter_id IS NOT NULL)
                      AS open_reporters
           FROM reports r
           LEFT JOIN listings l ON l.id = r.listing_id
           LEFT JOIN wanted_posts w ON w.id = r.wanted_post_id
           WHERE l.category_id = $1 OR w.category_id = $1
           GROUP BY r.target_type, r.target_id, l.title, w.title""", category_id)
    reporters: set = set()
    for r in reported:
        await log_moderation(conn, moderator_id, "delete_reported_post_with_category", r["target_type"],
                             r["target_id"], f"“{r['title']}” ({r['reports']} report(s)) removed with its category")
        reporters |= set(r["open_reporters"] or [])
    reporters.discard(moderator_id)
    if reporters:
        await create_notifications(conn, list(reporters), "moderation_action", {
            "message": "A Buy & Sell post you reported has been removed by a moderator.",
            "kind": "report_resolved"})


# What uses each table's categories: (label for the 409 message, table, column)
_USERS = {
    "bs_categories": [("listings", "listings", "category_id"), ("Wanted posts", "wanted_posts", "category_id"),
                      ("saved searches", "saved_searches", "bs_category_id")],
    "lf_categories": [("lost reports", "lost_reports", "category_id"), ("found reports", "found_reports", "category_id"),
                      ("saved searches", "saved_searches", "lf_category_id")],
}

_register("/buy-sell/categories", "bs_categories", "Buy & Sell", "buy_sell")
_register("/lost-found/categories", "lf_categories", "Lost & Found", "lost_found")
