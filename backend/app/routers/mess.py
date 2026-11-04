"""Mess menus and meal alerts (rev 18).

A mess (C Mess, A Mess, ...) posts its menu for a month: the PDF or photo it was shared as, and/or
what breakfast, lunch, snacks and dinner have on each weekday (repeating every week).

  guest / user           see each mess, today's meals and the menus
  user                   follow a mess and pick the meals to be alerted about (app/mess_alerts.py
                         sends "C Mess · Lunch at 12:30 pm today: ..." shortly before each one)
  events moderator/admin add messes and their meal times; add, edit and remove menus

Menus of one mess can't overlap, so every day has at most one menu.

Rev 20:
  - POST /mess-menus/extract reads the meals from an uploaded PDF or photo (app/mess_extract.py) to
    prefill the form; the moderator checks every cell before posting. Nothing is saved by it.
  - POST /mess-menus posts a menu by mess name, adding the mess if it's new.
  - Each mess has a Food/Mess event card (its meal times and what it serves), created with its first
    menu and rewritten whenever its menus or times change. The card isn't edited directly.
"""
import asyncio
import re
from collections import Counter
from datetime import date, datetime, time, timezone
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, field_validator, model_validator

from ..auth import CurrentUser, current_user, optional_user
from ..common import UserRef, forbidden, not_found
from ..db import get_conn
from ..mess_alerts import IST, MEAL_NAMES, MEALS
from ..mess_extract import extract_menu
from ..permissions import is_module_moderator, log_moderation
from ..storage import delete_objects, file_url, get_object, mark_attached, verify_own_uploads

router = APIRouter(tags=["Mess Menus"])

Meal = Literal["breakfast", "lunch", "snacks", "dinner"]
MODULE = "events"
MAX_MENU_DAYS = 93


class MealTimes(BaseModel):
    breakfast: time = time(7, 30)
    lunch: time = time(12, 30)
    snacks: time = time(16, 45)
    dinner: time = time(19, 30)


class MessIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    meal_times: MealTimes = Field(default_factory=MealTimes, description="When each meal starts, India time")

    @field_validator("name")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("name can't be blank")
        return v


class MessUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=60)
    meal_times: MealTimes | None = None


class MenuItem(BaseModel):
    weekday: int = Field(ge=1, le=7, description="1 = Monday ... 7 = Sunday")
    meal: Meal
    items: str = Field(min_length=1, max_length=1000, description="The dishes, as written on the menu")

    @field_validator("items")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("items can't be blank")
        return v


def _unique_cells(items: list[MenuItem]) -> list[MenuItem]:
    seen = set()
    for i in items:
        if (i.weekday, i.meal) in seen:
            raise ValueError(f"{i.meal} on weekday {i.weekday} is given twice")
        seen.add((i.weekday, i.meal))
    return items


class MenuIn(BaseModel):
    valid_from: date
    valid_to: date
    file_s3_key: str | None = Field(None, description="The menu as a PDF or image: s3_key from POST /uploads "
                                                      "(kind mess_menu)")
    notes: str | None = Field(None, max_length=2000)
    items: list[MenuItem] = Field(default_factory=list, max_length=28,
                                  description="The dishes; may be empty when the menu is only the file")

    @model_validator(mode="after")
    def _check(self):
        if not self.items and not self.file_s3_key:
            raise ValueError("Attach the menu as a PDF or photo, or type in at least one meal")
        if self.valid_to < self.valid_from:
            raise ValueError("valid_to is before valid_from")
        if (self.valid_to - self.valid_from).days >= MAX_MENU_DAYS:
            raise ValueError("A menu can cover at most about three months; post the next one separately")
        _unique_cells(self.items)
        return self


class MenuUpdate(BaseModel):
    valid_from: date | None = None
    valid_to: date | None = None
    file_s3_key: str | None = Field(None, description="A new file's s3_key, or null to remove the file")
    notes: str | None = Field(None, max_length=2000)
    items: list[MenuItem] | None = Field(None, max_length=28, description="Replaces every cell of the menu")

    @field_validator("items")
    @classmethod
    def _unique(cls, v):
        return _unique_cells(v) if v is not None else v


class Menu(BaseModel):
    id: UUID
    mess_id: int
    mess_name: str
    valid_from: date
    valid_to: date
    file_url: str | None = Field(None, description="Short-lived link to the menu's PDF or image")
    file_type: Literal["pdf", "image"] | None = None
    notes: str | None
    items: list[MenuItem]
    created_by: UserRef
    updated_at: datetime


class TodayMeal(BaseModel):
    meal: Meal
    starts_at: datetime
    items: str


class Mess(BaseModel):
    id: int
    name: str
    meal_times: MealTimes
    following_meals: list[Meal] | None = Field(None, description="The meals you get alerts for; null if you "
                                                                 "don't follow this mess (always null for guests)")
    follower_count: int
    current_menu_id: UUID | None = Field(None, description="The menu in force today, if any")
    next_menu_from: date | None = Field(None, description="When the next menu starts, if one is posted")
    today: list[TodayMeal] = Field(description="Today's meals in order (empty without a menu for today)")


class MessList(BaseModel):
    messes: list[Mess]
    can_manage: bool = Field(description="Whether you can add messes and menus (events moderator or admin)")


class FollowIn(BaseModel):
    meals: list[Meal] = Field(description="Meals to be alerted about; an empty list unfollows the mess")


def _today() -> date:
    return datetime.now(timezone.utc).astimezone(IST).date()


async def _can_manage(conn: asyncpg.Connection, user: CurrentUser | None) -> bool:
    return user is not None and await is_module_moderator(conn, user, MODULE)


async def _require_manager(conn: asyncpg.Connection, user: CurrentUser) -> None:
    if not await _can_manage(conn, user):
        raise forbidden("Only Events moderators can manage mess menus.")


_MESS_SELECT = """
SELECT m.*, f.meals AS following_meals,
       (SELECT count(*) FROM mess_follows x WHERE x.mess_id = m.id)::int AS follower_count,
       cur.id AS current_menu_id,
       (SELECT min(n.valid_from) FROM mess_menus n WHERE n.mess_id = m.id AND n.valid_from > $2) AS next_menu_from,
       coalesce((SELECT jsonb_agg(jsonb_build_object('meal', i.meal, 'items', i.items))
                 FROM mess_menu_items i WHERE i.menu_id = cur.id AND i.weekday = $3), '[]') AS today
FROM messes m
LEFT JOIN mess_follows f ON f.mess_id = m.id AND f.user_id = $1
LEFT JOIN mess_menus cur ON cur.mess_id = m.id AND $2 BETWEEN cur.valid_from AND cur.valid_to
"""


def _mess(r: asyncpg.Record) -> Mess:
    day = _today()
    times = MealTimes(breakfast=r["breakfast_at"], lunch=r["lunch_at"], snacks=r["snacks_at"], dinner=r["dinner_at"])
    cells = {c["meal"]: c["items"] for c in r["today"]}
    today = [TodayMeal(meal=m, starts_at=datetime.combine(day, getattr(times, m), tzinfo=IST), items=cells[m])
             for m in MEALS if m in cells]
    meals = r["following_meals"]
    return Mess(id=r["id"], name=r["name"], meal_times=times,
                following_meals=[m for m in MEALS if m in meals] if meals is not None else None,
                follower_count=r["follower_count"], current_menu_id=r["current_menu_id"],
                next_menu_from=r["next_menu_from"], today=today)


async def _mess_detail(conn: asyncpg.Connection, mess_id: int, viewer: CurrentUser | None) -> Mess:
    day = _today()
    r = await conn.fetchrow(_MESS_SELECT + " WHERE m.id = $4", viewer.id if viewer else None, day,
                            day.isoweekday(), mess_id)
    if r is None:
        raise not_found("Mess")
    return _mess(r)


@router.get("/messes", response_model=MessList, summary="Every mess with today's meals (guests allowed)")
async def list_messes(viewer: CurrentUser | None = Depends(optional_user), conn: asyncpg.Connection = Depends(get_conn)):
    day = _today()
    rows = await conn.fetch(_MESS_SELECT + " ORDER BY m.name", viewer.id if viewer else None, day, day.isoweekday())
    return MessList(messes=[_mess(r) for r in rows], can_manage=await _can_manage(conn, viewer))


def _times(body: MealTimes) -> list[time]:
    return [body.breakfast, body.lunch, body.snacks, body.dinner]


@router.post("/messes", response_model=Mess, status_code=201, summary="Add a mess (Events moderator or admin)")
async def create_mess(body: MessIn, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _require_manager(conn, user)
    if await conn.fetchval("SELECT EXISTS (SELECT 1 FROM messes WHERE lower(name) = lower($1))", body.name):
        raise HTTPException(409, f"There's already a mess called {body.name}.")
    async with conn.transaction():
        try:
            mess_id = await conn.fetchval(
                """INSERT INTO messes (name, breakfast_at, lunch_at, snacks_at, dinner_at)
                   VALUES ($1, $2, $3, $4, $5) RETURNING id""", body.name, *_times(body.meal_times))
        except asyncpg.UniqueViolationError as exc:
            raise HTTPException(409, f"There's already a mess called {body.name}.") from exc
        await log_moderation(conn, user.id, "create_mess", "mess", _mess_uuid(mess_id), body.name)
    return await _mess_detail(conn, mess_id, user)


def _mess_uuid(mess_id: int) -> UUID:
    """moderation_log.target_id is a UUID; messes have small integer ids."""
    return UUID(int=mess_id)


@router.patch("/messes/{mess_id}", response_model=Mess, summary="Rename a mess or change its meal times "
                                                                "(Events moderator or admin)")
async def update_mess(mess_id: int, body: MessUpdate, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _require_manager(conn, user)
    async with conn.transaction():
        if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM messes WHERE id = $1)", mess_id):
            raise not_found("Mess")
        try:
            if body.name is not None:
                await conn.execute("UPDATE messes SET name = $2 WHERE id = $1", mess_id, " ".join(body.name.split()))
        except asyncpg.UniqueViolationError as exc:
            raise HTTPException(409, f"There's already a mess called {body.name}.") from exc
        if body.meal_times is not None:
            await conn.execute("UPDATE messes SET breakfast_at = $2, lunch_at = $3, snacks_at = $4, dinner_at = $5 "
                               "WHERE id = $1", mess_id, *_times(body.meal_times))
        await log_moderation(conn, user.id, "edit_mess", "mess", _mess_uuid(mess_id))
        await sync_mess_event(conn, mess_id, user.id)
    return await _mess_detail(conn, mess_id, user)


@router.delete("/messes/{mess_id}", status_code=204,
               summary="Remove a mess with its menus and followers (Events moderator or admin)")
async def delete_mess(mess_id: int, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _require_manager(conn, user)
    async with conn.transaction():
        files = [r["file_s3_key"] for r in await conn.fetch(
            "SELECT file_s3_key FROM mess_menus WHERE mess_id = $1 AND file_s3_key IS NOT NULL", mess_id)]
        event_id = await conn.fetchval("SELECT event_id FROM messes WHERE id = $1", mess_id)
        if not await conn.fetchval("DELETE FROM messes WHERE id = $1 RETURNING true", mess_id):
            raise not_found("Mess")
        if event_id:
            await conn.execute("UPDATE events SET deleted_at = now(), deleted_by = $2 WHERE id = $1 AND deleted_at IS NULL",
                               event_id, user.id)
        await log_moderation(conn, user.id, "delete_mess", "mess", _mess_uuid(mess_id))
    await delete_objects(files)
    return Response(status_code=204)


@router.put("/messes/{mess_id}/follow", response_model=Mess,
            summary="Choose the meals to be alerted about; no meals unfollows")
async def follow_mess(mess_id: int, body: FollowIn, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM messes WHERE id = $1)", mess_id):
        raise not_found("Mess")
    meals = [m for m in MEALS if m in body.meals]
    if meals:
        await conn.execute(
            """INSERT INTO mess_follows (user_id, mess_id, meals) VALUES ($1, $2, $3)
               ON CONFLICT (user_id, mess_id) DO UPDATE SET meals = EXCLUDED.meals""", user.id, mess_id, meals)
    else:
        await conn.execute("DELETE FROM mess_follows WHERE user_id = $1 AND mess_id = $2", user.id, mess_id)
    return await _mess_detail(conn, mess_id, user)


# ---------------------------------------------------------------- menus
_MENU_SELECT = """
SELECT mm.*, m.name AS mess_name, u.name AS creator_name,
       coalesce((SELECT jsonb_agg(jsonb_build_object('weekday', i.weekday, 'meal', i.meal, 'items', i.items)
                                  ORDER BY i.weekday, array_position(ARRAY['breakfast','lunch','snacks','dinner'], i.meal))
                 FROM mess_menu_items i WHERE i.menu_id = mm.id), '[]') AS items
FROM mess_menus mm JOIN messes m ON m.id = mm.mess_id JOIN users u ON u.id = mm.created_by
"""


def _menu(r: asyncpg.Record) -> Menu:
    key = r["file_s3_key"]
    return Menu(id=r["id"], mess_id=r["mess_id"], mess_name=r["mess_name"], valid_from=r["valid_from"],
                valid_to=r["valid_to"], file_url=file_url(key) if key else None,
                file_type=("pdf" if key.lower().endswith(".pdf") else "image") if key else None, notes=r["notes"],
                items=[MenuItem(**i) for i in r["items"]], created_by=UserRef(id=r["created_by"], name=r["creator_name"]),
                updated_at=r["updated_at"])


async def _menu_detail(conn: asyncpg.Connection, menu_id: UUID) -> Menu:
    r = await conn.fetchrow(_MENU_SELECT + " WHERE mm.id = $1", menu_id)
    if r is None:
        raise not_found("Menu")
    return _menu(r)


@router.get("/messes/{mess_id}/menus", response_model=list[Menu],
            summary="A mess's current and upcoming menus, then the last few past ones (guests allowed)")
async def list_menus(mess_id: int, past: int = Query(3, ge=0, le=24, description="How many past menus to include"),
                     conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM messes WHERE id = $1)", mess_id):
        raise not_found("Mess")
    day = _today()
    rows = await conn.fetch(
        f"""({_MENU_SELECT} WHERE mm.mess_id = $1 AND mm.valid_to >= $2 ORDER BY mm.valid_from)
            UNION ALL
            (SELECT * FROM ({_MENU_SELECT} WHERE mm.mess_id = $1 AND mm.valid_to < $2
                            ORDER BY mm.valid_from DESC LIMIT $3) p)""", mess_id, day, past)
    return [_menu(r) for r in rows]


@router.get("/mess-menus/{menu_id}", response_model=Menu, summary="One menu with every meal (guests allowed)")
async def get_menu(menu_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    return await _menu_detail(conn, menu_id)


async def _check_overlap(conn: asyncpg.Connection, mess_id: int, start: date, end: date,
                         menu_id: UUID | None = None) -> None:
    other = await conn.fetchrow(
        """SELECT valid_from, valid_to FROM mess_menus WHERE mess_id = $1 AND valid_from <= $3 AND valid_to >= $2
             AND ($4::uuid IS NULL OR id <> $4) LIMIT 1""", mess_id, start, end, menu_id)
    if other:
        raise HTTPException(409, f"This mess already has a menu for {other['valid_from']:%-d %b} to "
                                 f"{other['valid_to']:%-d %b %Y}. Change the dates, or edit that menu instead.")


async def _replace_older_menus(conn: asyncpg.Connection, mess_id: int, start: date, end: date,
                               user_id: UUID) -> list[str]:
    """A new menu replaces what the mess had for its dates. A menu that started earlier now ends the day
    before (its earlier days stay as history); one that starts on or after the new menu's first day and
    overlaps it is removed. Returns the removed menus' files, to delete once the change is saved."""
    trimmed = await conn.fetch(
        """UPDATE mess_menus SET valid_to = $2::date - 1, updated_at = now()
            WHERE mess_id = $1 AND valid_from < $2 AND valid_to >= $2 RETURNING id""", mess_id, start)
    removed = await conn.fetch(
        """DELETE FROM mess_menus WHERE mess_id = $1 AND valid_from >= $2 AND valid_from <= $3
            RETURNING id, file_s3_key""", mess_id, start, end)
    for r in [*trimmed, *removed]:
        await log_moderation(conn, user_id, "replace_mess_menu", "mess_menu", r["id"])
    return [r["file_s3_key"] for r in removed if r["file_s3_key"]]


async def _save_items(conn: asyncpg.Connection, menu_id: UUID, items: list[MenuItem]) -> None:
    await conn.execute("DELETE FROM mess_menu_items WHERE menu_id = $1", menu_id)
    await conn.executemany("INSERT INTO mess_menu_items (menu_id, weekday, meal, items) VALUES ($1, $2, $3, $4)",
                           [(menu_id, i.weekday, i.meal, i.items) for i in items])


@router.post("/messes/{mess_id}/menus", response_model=Menu, status_code=201,
             summary="Post a menu for some weeks (Events moderator or admin)")
async def create_menu(mess_id: int, body: MenuIn, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _require_manager(conn, user)
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM messes WHERE id = $1)", mess_id):
        raise not_found("Mess")
    if body.file_s3_key:
        await verify_own_uploads([body.file_s3_key], "mess_menu", user.id)
    async with conn.transaction():
        replaced_files = await _replace_older_menus(conn, mess_id, body.valid_from, body.valid_to, user.id)
        replaced_files = [k for k in replaced_files if k != body.file_s3_key]
        menu_id = await conn.fetchval(
            """INSERT INTO mess_menus (mess_id, valid_from, valid_to, file_s3_key, notes, created_by)
               VALUES ($1, $2, $3, $4, $5, $6) RETURNING id""",
            mess_id, body.valid_from, body.valid_to, body.file_s3_key, (body.notes or "").strip() or None, user.id)
        await _save_items(conn, menu_id, body.items)
        await log_moderation(conn, user.id, "create_mess_menu", "mess_menu", menu_id)
        await sync_mess_event(conn, mess_id, user.id)
    if body.file_s3_key:
        await mark_attached([body.file_s3_key])
    await delete_objects(replaced_files)
    return await _menu_detail(conn, menu_id)


@router.patch("/mess-menus/{menu_id}", response_model=Menu, summary="Edit a menu (Events moderator or admin)")
async def update_menu(menu_id: UUID, body: MenuUpdate, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _require_manager(conn, user)
    changes = body.model_dump(exclude_unset=True)
    if changes.get("file_s3_key"):
        await verify_own_uploads([changes["file_s3_key"]], "mess_menu", user.id)
    old_file = None
    async with conn.transaction():
        old = await conn.fetchrow("SELECT * FROM mess_menus WHERE id = $1 FOR UPDATE", menu_id)
        if old is None:
            raise not_found("Menu")
        start = changes.get("valid_from") or old["valid_from"]
        end = changes.get("valid_to") or old["valid_to"]
        if end < start:
            raise HTTPException(422, "valid_to is before valid_from.")
        if (end - start).days >= MAX_MENU_DAYS:
            raise HTTPException(422, "A menu can cover at most about three months.")
        await _check_overlap(conn, old["mess_id"], start, end, menu_id)
        notes = (changes["notes"] or "").strip() or None if "notes" in changes else old["notes"]
        new_file = changes["file_s3_key"] if "file_s3_key" in changes else old["file_s3_key"]
        if new_file != old["file_s3_key"]:
            old_file = old["file_s3_key"]
        await conn.execute(
            """UPDATE mess_menus SET valid_from = $2, valid_to = $3, notes = $4, file_s3_key = $5, updated_at = now()
               WHERE id = $1""", menu_id, start, end, notes, new_file)
        if body.items is not None:
            await _save_items(conn, menu_id, body.items)
        if not new_file and not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM mess_menu_items WHERE menu_id = $1)",
                                                    menu_id):
            raise HTTPException(422, "A menu needs its file or at least one meal typed in.")
        await log_moderation(conn, user.id, "edit_mess_menu", "mess_menu", menu_id)
        await sync_mess_event(conn, old["mess_id"], user.id)
    if changes.get("file_s3_key"):
        await mark_attached([changes["file_s3_key"]])
    if old_file:
        await delete_objects([old_file])
    return await _menu_detail(conn, menu_id)


@router.delete("/mess-menus/{menu_id}", status_code=204, summary="Remove a menu (Events moderator or admin)")
async def delete_menu(menu_id: UUID, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _require_manager(conn, user)
    async with conn.transaction():
        key = await conn.fetchrow("DELETE FROM mess_menus WHERE id = $1 RETURNING file_s3_key, mess_id", menu_id)
        if key is None:
            raise not_found("Menu")
        await log_moderation(conn, user.id, "delete_mess_menu", "mess_menu", menu_id)
        await sync_mess_event(conn, key["mess_id"], user.id)
    if key["file_s3_key"]:
        await delete_objects([key["file_s3_key"]])
    return Response(status_code=204)


# ---------------------------------------------------------------- the mess's event card (rev 20)
def _dishes(cells: list[str], limit: int = 7) -> list[str]:
    """The dishes a meal serves most often over the week, in the menu's own words."""
    counts: Counter[str] = Counter()
    first: dict[str, str] = {}
    for cell in cells:
        for part in re.split(r"[,/+;]|\.\s", cell):
            dish = " ".join(part.split()).strip(" .-*()")
            if 3 <= len(dish) <= 40 and dish.upper() != "RRBM":
                key = dish.lower()
                counts[key] += 1
                first.setdefault(key, dish)
    return [first[k] for k, _ in counts.most_common(limit)]


def _clock(t: time) -> str:
    return t.strftime("%-I:%M %p").lower()


async def sync_mess_event(conn: asyncpg.Connection, mess_id: int, user_id: UUID) -> None:
    """Create or rewrite the mess's Food/Mess event card from its current and upcoming menus: when it's
    open, and what each meal usually has. No menus left: the card is removed."""
    mess = await conn.fetchrow("SELECT * FROM messes WHERE id = $1", mess_id)
    if mess is None:
        return
    today = _today()
    menus = await conn.fetch(
        """SELECT * FROM mess_menus WHERE mess_id = $1 AND valid_to >= $2 ORDER BY valid_from""", mess_id, today)
    if not menus:
        menus = await conn.fetch("SELECT * FROM mess_menus WHERE mess_id = $1 ORDER BY valid_to DESC LIMIT 1", mess_id)
    if not menus:
        if mess["event_id"]:
            await conn.execute("UPDATE events SET deleted_at = now(), deleted_by = $2 WHERE id = $1 AND deleted_at IS NULL",
                               mess["event_id"], user_id)
            await conn.execute("UPDATE messes SET event_id = NULL WHERE id = $1", mess_id)
        return
    current = menus[0]
    cells = await conn.fetch("SELECT meal, items FROM mess_menu_items WHERE menu_id = $1", current["id"])
    lines = ["Meal times: " + " · ".join(f"{MEAL_NAMES[m]} {_clock(mess[m + '_at'])}" for m in MEALS), ""]
    for meal in MEALS:
        dishes = _dishes([c["items"] for c in cells if c["meal"] == meal])
        if dishes:
            lines.append(f"{MEAL_NAMES[meal]}: {', '.join(dishes)}")
    if not cells:
        lines.append("The menu was posted as a file: open the mess menu to see each day's meals.")
    if current["notes"]:
        lines += ["", current["notes"]]
    lines += ["", "See every day's menu and get meal alerts on the Mess menu page."]
    start = datetime.combine(min(m["valid_from"] for m in menus), time(0, 0), tzinfo=IST)
    end = datetime.combine(max(m["valid_to"] for m in menus), time(23, 59), tzinfo=IST)
    title = f"{mess['name']}: what's on the menu"
    description = "\n".join(lines)[:5000]
    event_id = mess["event_id"]
    alive = event_id and await conn.fetchval("SELECT deleted_at IS NULL FROM events WHERE id = $1", event_id)
    if alive:
        await conn.execute(
            """UPDATE events SET title = $2, description = $3, location = $4, start_time = $5, end_time = $6,
                                 updated_at = now() WHERE id = $1""", event_id, title, description, mess["name"], start, end)
        return
    tag_id = await conn.fetchval("SELECT id FROM event_tags WHERE name ILIKE 'food%' ORDER BY id LIMIT 1")
    if tag_id is None:
        tag_id = await conn.fetchval("INSERT INTO event_tags (name) VALUES ('Food/Mess') RETURNING id")
    event_id = await conn.fetchval(
        """INSERT INTO events (created_by, title, description, location, start_time, end_time)
           VALUES ($1, $2, $3, $4, $5, $6) RETURNING id""", user_id, title, description, mess["name"], start, end)
    await conn.execute("INSERT INTO event_tag_map (event_id, tag_id) VALUES ($1, $2)", event_id, tag_id)
    await conn.execute("UPDATE messes SET event_id = $2 WHERE id = $1", mess_id, event_id)


# ---------------------------------------------------------------- reading a menu file (rev 20)
class ExtractIn(BaseModel):
    file_s3_key: str = Field(description="The menu PDF or photo, uploaded with POST /uploads (kind mess_menu)")


class Extracted(BaseModel):
    mess_name: str | None = Field(None, description="The mess named in the file's title, e.g. C Mess")
    month: date | None = Field(None, description="First day of the month the title names, if any")
    starts: date | None = Field(None, description="The date the menu says it's effective from, if any")
    items: list[MenuItem]
    notes: str | None
    warnings: list[str] = Field(description="What couldn't be read; show these above the form")


@router.post("/mess-menus/extract", response_model=Extracted,
             summary="Read the meals from an uploaded menu file to prefill the form (Events moderator or admin)")
async def extract(body: ExtractIn, user: CurrentUser = Depends(current_user),
                  conn: asyncpg.Connection = Depends(get_conn)):
    """Nothing is saved: show the result for the moderator to check and correct, then post it with
    POST /mess-menus. Takes a few seconds for a one-page menu."""
    await _require_manager(conn, user)
    await verify_own_uploads([body.file_s3_key], "mess_menu", user.id)
    data, content_type = await get_object(body.file_s3_key)
    found = await asyncio.to_thread(extract_menu, data, content_type)
    items = []
    for (day, meal), dishes in sorted(found.items.items()):
        try:
            items.append(MenuItem(weekday=day, meal=meal, items=dishes[:1000]))
        except ValueError:
            continue
    return Extracted(mess_name=found.mess_name, month=found.month, starts=found.starts, items=items,
                     notes=found.notes[:2000] if found.notes else None, warnings=found.warnings)


class NamedMenuIn(MenuIn):
    mess_name: str = Field(min_length=1, max_length=60, description="An existing mess, or a new one to add")
    meal_times: MealTimes | None = Field(None, description="For a new mess; defaults otherwise")


@router.post("/mess-menus", response_model=Menu, status_code=201,
             summary="Post a menu by mess name, adding the mess if it's new (Events moderator or admin)")
async def create_named_menu(body: NamedMenuIn, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
    await _require_manager(conn, user)
    name = " ".join(body.mess_name.split())
    mess_id = await conn.fetchval("SELECT id FROM messes WHERE lower(name) = lower($1)", name)
    if mess_id is None:
        mess_id = await conn.fetchval(
            """INSERT INTO messes (name, breakfast_at, lunch_at, snacks_at, dinner_at) VALUES ($1, $2, $3, $4, $5)
               ON CONFLICT (name) DO UPDATE SET name = messes.name RETURNING id""",
            name, *_times(body.meal_times or MealTimes()))
        await log_moderation(conn, user.id, "create_mess", "mess", _mess_uuid(mess_id), name)
    return await create_menu(mess_id, MenuIn(**body.model_dump(exclude={"mess_name", "meal_times"})), user, conn)
