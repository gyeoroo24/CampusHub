"""Community / culture events (FR-18 to FR-20, FR-22) and bookmarks.

  guest   browse events by tag and time (Past / Present / Upcoming, worked out from the clock, FR-19);
          bookmarks stay on the device (the app imports them after sign-in)
  user    bookmark events and listings; follow tags; discuss an event in its forum
          (GET /events/{id}/forum in forums.py)
  events moderator / admin
          create events (optionally with a poster image; rev 21: only they can), edit/remove any event;
          manage the tag list; remove posts in event forums

Alerts (FR-20, FR-22):
  followed_tag_event        a new event carries a tag you follow (or a tag you follow is added to one)
  bookmarked_event_update   an event you bookmarked changed its time, place, title or details, or was cancelled
Nobody is alerted about their own changes, or about events that are already over.
"""
from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, model_validator

from ..auth import CurrentUser, current_user, optional_user
from ..common import (MAX_INT_ID, CategoryRef, Page, PageParams, UserRef, forbidden, like_pattern, make_page,
                      not_found, page_params, search_text, set_clause, text)
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import is_module_moderator, log_moderation
from ..storage import delete_objects, file_url, mark_attached, verify_own_uploads

router = APIRouter(tags=["Community Events"])

EventWhen = Literal["upcoming", "present", "past"]
TagId = Annotated[int, Field(ge=1, le=MAX_INT_ID)]
MAX_TAGS = 5
MAX_DURATION = timedelta(days=30)
MAX_AHEAD = timedelta(days=400)
IST = timezone(timedelta(hours=5, minutes=30), "IST")


def _when_text(start: datetime) -> str:
    """'Sat 8 Nov, 5:30 pm' in IST, for alert messages."""
    t = start.astimezone(IST)
    return f"{t:%a} {t.day} {t:%b}, {t.hour % 12 or 12}:{t:%M} {'am' if t.hour < 12 else 'pm'}"


def _aware(value: datetime | None, name: str) -> None:
    if value is not None and value.tzinfo is None:
        raise ValueError(f"{name} needs a timezone, e.g. 2026-11-08T17:30:00+05:30")


# ---------------------------------------------------------------- models
class EventCreate(BaseModel):
    title: text(150) = Field(examples=["Bird walk around the campus"])
    description: text(5000, min_length=0) | None = None
    location: text(200, min_length=0) | None = Field(None, examples=["Main gate"])
    start_time: datetime
    end_time: datetime
    tag_ids: list[TagId] = Field(min_length=1, max_length=MAX_TAGS, description="1 to 5 tags")
    poster_s3_key: str | None = Field(None, description="Optional poster: s3_key from POST /uploads (kind event_poster)")

    @model_validator(mode="after")
    def _times(self):
        _aware(self.start_time, "start_time")
        _aware(self.end_time, "end_time")
        if self.end_time <= self.start_time:
            raise ValueError("end_time must be after start_time")
        if self.end_time - self.start_time > MAX_DURATION:
            raise ValueError("An event can last at most 30 days")
        if self.start_time > datetime.now(timezone.utc) + MAX_AHEAD:
            raise ValueError("start_time is more than a year away")
        return self


class EventUpdate(BaseModel):
    title: text(150) | None = None
    description: text(5000, min_length=0) | None = None
    location: text(200, min_length=0) | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None
    tag_ids: list[TagId] | None = Field(None, min_length=1, max_length=MAX_TAGS)
    poster_s3_key: str | None = Field(None, description="A new poster's s3_key, or null to remove the poster")

    @model_validator(mode="after")
    def _times(self):
        _aware(self.start_time, "start_time")
        _aware(self.end_time, "end_time")
        return self


class TagIn(BaseModel):
    name: text(40) = Field(examples=["Photography"])


class EventTag(BaseModel):
    id: int
    name: str
    upcoming_count: int = Field(description="Events with this tag that haven't ended")
    following: bool = Field(description="The viewer follows this tag (always false for guests)")


class Event(BaseModel):
    id: UUID
    title: str
    description: str | None
    location: str | None
    start_time: datetime
    end_time: datetime
    when: EventWhen = Field(description="Worked out from the current time (FR-19)")
    tags: list[CategoryRef]
    poster_url: str | None = Field(None, description="Short-lived link to the poster image, if any")
    organizer: UserRef
    bookmark_count: int
    is_bookmarked: bool = Field(description="The viewer bookmarked it (always false for guests)")
    can_edit: bool = Field(description="The viewer created it, or is an events moderator or admin")
    mess_id: int | None = Field(None, description="This is a mess's card (rev 20): its menu is at GET /messes, "
                                                  "and it's kept in step with the menu, so edit the menu instead")
    created_at: datetime
    updated_at: datetime


BookmarkTarget = Literal["listing", "event"]


class Bookmark(BaseModel):
    target_type: BookmarkTarget
    target_id: UUID
    created_at: datetime


class BookmarkRef(BaseModel):
    target_type: BookmarkTarget
    target_id: UUID


class BookmarkImport(BaseModel):
    items: list[BookmarkRef] = Field(max_length=500, description="Bookmarks a guest kept on the device")


class BookmarkImportResult(BaseModel):
    added: int
    already_saved: int
    skipped: int = Field(description="Items that no longer exist")


# ---------------------------------------------------------------- queries
_WHEN = ("CASE WHEN now() < e.start_time THEN 'upcoming' WHEN now() <= e.end_time THEN 'present' "
         "ELSE 'past' END")

# $1 = viewer id (NULL for guests)
_SELECT = f"""
SELECT e.id, e.title, e.description, e.location, e.start_time, e.end_time, e.created_at, e.updated_at,
       e.created_by, e.poster_s3_key, u.name AS organizer_name, {_WHEN} AS phase,
       (SELECT ms.id FROM messes ms WHERE ms.event_id = e.id) AS mess_id,
       (SELECT coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name) ORDER BY t.name), '[]'::jsonb)
        FROM event_tag_map m JOIN event_tags t ON t.id = m.tag_id WHERE m.event_id = e.id) AS tags,
       (SELECT count(*) FROM bookmarks b WHERE b.target_type = 'event' AND b.target_id = e.id) AS bookmark_count,
       EXISTS (SELECT 1 FROM bookmarks b WHERE b.target_type = 'event' AND b.target_id = e.id
                                          AND b.user_id = $1) AS is_bookmarked
FROM events e JOIN users u ON u.id = e.created_by
"""


def _event(r: asyncpg.Record, viewer: CurrentUser | None, moderator: bool = False) -> Event:
    key = r["poster_s3_key"]
    return Event(id=r["id"], title=r["title"], description=r["description"], location=r["location"],
                 start_time=r["start_time"], end_time=r["end_time"], when=r["phase"],
                 tags=[CategoryRef(**t) for t in r["tags"]], poster_url=file_url(key) if key else None,
                 organizer=UserRef(id=r["created_by"], name=r["organizer_name"]),
                 bookmark_count=r["bookmark_count"], is_bookmarked=r["is_bookmarked"],
                 can_edit=viewer is not None and r["mess_id"] is None and (moderator or viewer.id == r["created_by"]),
                 mess_id=r["mess_id"],
                 created_at=r["created_at"], updated_at=r["updated_at"])


async def _is_moderator(conn: asyncpg.Connection, viewer: CurrentUser | None) -> bool:
    """Events moderator or admin."""
    return viewer is not None and await is_module_moderator(conn, viewer, "events")


async def _event_detail(conn: asyncpg.Connection, event_id: UUID, viewer: CurrentUser | None) -> Event:
    r = await conn.fetchrow(_SELECT + " WHERE e.id = $2 AND e.deleted_at IS NULL",
                            viewer.id if viewer else None, event_id)
    if r is None:
        raise not_found("Event")
    return _event(r, viewer, await _is_moderator(conn, viewer))


async def _check_tags(conn: asyncpg.Connection, tag_ids: list[int]) -> list[int]:
    tag_ids = list(dict.fromkeys(tag_ids))
    found = await conn.fetchval("SELECT count(*) FROM event_tags WHERE id = ANY($1::int[])", tag_ids)
    if found != len(tag_ids):
        raise HTTPException(422, "tag_ids has a tag that doesn't exist. See GET /event-tags.")
    return tag_ids


async def _tag_names(conn: asyncpg.Connection, tag_ids: list[int]) -> list[str]:
    return [r["name"] for r in await conn.fetch(
        "SELECT name FROM event_tags WHERE id = ANY($1::int[]) ORDER BY name", tag_ids)]


async def _notify_followers(conn: asyncpg.Connection, event_id: UUID, title: str, start: datetime,
                            tag_ids: list[int], exclude: list[UUID]) -> tuple[list[UUID], dict]:
    """followed_tag_event to everyone following one of these tags, except the excluded users."""
    followers = [r["user_id"] for r in await conn.fetch(
        """SELECT DISTINCT f.user_id FROM tag_follows f JOIN users u ON u.id = f.user_id AND u.is_active
           WHERE f.tag_id = ANY($1::int[]) AND NOT (f.user_id = ANY($2::uuid[]))""", tag_ids, exclude)]
    names = await _tag_names(conn, tag_ids)
    payload = {"event_id": str(event_id), "tags": names,
               "message": f"New {' / '.join(names)} event: “{title}”, {_when_text(start)}"}
    return await create_notifications(conn, followers, "followed_tag_event", payload), payload


async def _bookmarkers(conn: asyncpg.Connection, event_id: UUID, exclude: UUID) -> list[UUID]:
    return [r["user_id"] for r in await conn.fetch(
        """SELECT b.user_id FROM bookmarks b JOIN users u ON u.id = b.user_id AND u.is_active
           WHERE b.target_type = 'event' AND b.target_id = $1 AND b.user_id <> $2""", event_id, exclude)]


async def _editable(conn: asyncpg.Connection, event_id: UUID, user: CurrentUser) -> asyncpg.Record:
    row = await conn.fetchrow(
        "SELECT * FROM events WHERE id = $1 AND deleted_at IS NULL FOR UPDATE", event_id)
    if row is None:
        raise not_found("Event")
    if row["created_by"] != user.id and not await _is_moderator(conn, user):
        raise forbidden("Only the organizer or an events moderator can change this event.")
    return row


# ---------------------------------------------------------------- tags
_TAG_SELECT = """
SELECT t.id, t.name,
       (SELECT count(*) FROM event_tag_map m JOIN events e ON e.id = m.event_id
        WHERE m.tag_id = t.id AND e.deleted_at IS NULL AND e.end_time >= now()) AS upcoming_count,
       EXISTS (SELECT 1 FROM tag_follows f WHERE f.tag_id = t.id AND f.user_id = $1) AS following
FROM event_tags t
"""


@router.get("/event-tags", response_model=list[EventTag], summary="All event tags (guests allowed)")
async def list_tags(viewer: CurrentUser | None = Depends(optional_user), conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(_TAG_SELECT + " ORDER BY t.name", viewer.id if viewer else None)
    return [EventTag(**dict(r)) for r in rows]


@router.post("/event-tags", response_model=EventTag, status_code=201, summary="Add a tag (events moderator or admin)")
async def create_tag(body: TagIn, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    if not await _is_moderator(conn, user):
        raise forbidden("Only an events moderator or admin can add event tags.")
    try:
        tag_id = await conn.fetchval("INSERT INTO event_tags (name) VALUES ($1) RETURNING id", body.name)
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, f"There's already a tag called “{body.name}”.") from exc
    return EventTag(id=tag_id, name=body.name, upcoming_count=0, following=False)


@router.patch("/event-tags/{tag_id}", response_model=EventTag, summary="Rename a tag (events moderator or admin)")
async def rename_tag(tag_id: int, body: TagIn, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    if not await _is_moderator(conn, user):
        raise forbidden("Only an events moderator or admin can rename event tags.")
    try:
        if not await conn.fetchval("UPDATE event_tags SET name = $2 WHERE id = $1 RETURNING true", tag_id, body.name):
            raise not_found("Tag")
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, f"There's already a tag called “{body.name}”.") from exc
    return EventTag(**dict(await conn.fetchrow(_TAG_SELECT + " WHERE t.id = $2", user.id, tag_id)))


@router.delete("/event-tags/{tag_id}", status_code=204,
               summary="Delete a tag (events moderator or admin). Events keep their other tags; followers of it are dropped")
async def delete_tag(tag_id: int, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    if not await _is_moderator(conn, user):
        raise forbidden("Only an events moderator or admin can delete event tags.")
    if not await conn.fetchval("DELETE FROM event_tags WHERE id = $1 RETURNING true", tag_id):
        raise not_found("Tag")
    return Response(status_code=204)


@router.get("/me/followed-tags", response_model=list[EventTag], summary="Tags I follow")
async def followed_tags(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(_TAG_SELECT + " WHERE EXISTS (SELECT 1 FROM tag_follows f WHERE f.tag_id = t.id "
                                          "AND f.user_id = $1) ORDER BY t.name", user.id)
    return [EventTag(**dict(r)) for r in rows]


@router.put("/me/followed-tags/{tag_id}", status_code=204, summary="Follow a tag: get alerts for its new events")
async def follow_tag(tag_id: int, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM event_tags WHERE id = $1)", tag_id):
        raise not_found("Tag")
    await conn.execute("INSERT INTO tag_follows (user_id, tag_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                       user.id, tag_id)
    return Response(status_code=204)


@router.delete("/me/followed-tags/{tag_id}", status_code=204, summary="Stop following a tag")
async def unfollow_tag(tag_id: int, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    await conn.execute("DELETE FROM tag_follows WHERE user_id = $1 AND tag_id = $2", user.id, tag_id)
    return Response(status_code=204)


# ---------------------------------------------------------------- events
@router.get("/events", response_model=Page[Event], summary="Browse events (guests allowed)")
async def list_events(
    when: list[EventWhen] | None = Query(
        None, description="Repeat to allow several. Default: present and upcoming. "
                          "Order: happening now, then soonest upcoming, then most recent past"),
    tag_id: list[int] | None = Query(None, description="Events carrying any of these tags (FR-18)"),
    q: str | None = Query(None, max_length=200, description="Words in the title, description or place"),
    from_time: datetime | None = Query(None, description="Only events that end at or after this time"),
    to_time: datetime | None = Query(None, description="Only events that start at or before this time"),
    organizer_id: UUID | None = None,
    bookmarked: bool = Query(False, description="Only events I bookmarked (signed in)"),
    page: PageParams = Depends(page_params),
    viewer: CurrentUser | None = Depends(optional_user),
    conn: asyncpg.Connection = Depends(get_conn),
):
    if bookmarked and viewer is None:
        raise HTTPException(401, "Sign in to see your bookmarked events.")
    if tag_id and any(not 1 <= t <= MAX_INT_ID for t in tag_id):
        raise HTTPException(422, "tag_id is out of range.")
    phases = list(dict.fromkeys(when or ["present", "upcoming"]))
    q = search_text(q)
    rows = await conn.fetch(
        f"""SELECT * FROM ({_SELECT} WHERE e.deleted_at IS NULL) x
        WHERE x.phase = ANY($2::text[])
          AND ($3::int[] IS NULL OR EXISTS (SELECT 1 FROM event_tag_map m
                                            WHERE m.event_id = x.id AND m.tag_id = ANY($3::int[])))
          AND ($4::text IS NULL OR x.title ILIKE '%' || $4 || '%' ESCAPE '\\'
                                OR x.description ILIKE '%' || $4 || '%' ESCAPE '\\'
                                OR x.location ILIKE '%' || $4 || '%' ESCAPE '\\')
          AND ($5::timestamptz IS NULL OR x.end_time >= $5)
          AND ($6::timestamptz IS NULL OR x.start_time <= $6)
          AND ($7::uuid IS NULL OR x.created_by = $7)
          AND (NOT $8::bool OR x.is_bookmarked)
        ORDER BY CASE x.phase WHEN 'present' THEN 0 WHEN 'upcoming' THEN 1 ELSE 2 END,
                 CASE WHEN x.phase = 'past' THEN NULL ELSE x.start_time END ASC,
                 x.start_time DESC, x.id
        LIMIT $9 OFFSET $10""",
        viewer.id if viewer else None, phases, tag_id or None, like_pattern(q) if q else None,
        from_time, to_time, organizer_id, bookmarked, page.limit + 1, page.offset)
    moderator = await _is_moderator(conn, viewer)
    return make_page(rows, page, lambda r: _event(r, viewer, moderator))


@router.get("/events/{event_id}", response_model=Event, summary="One event")
async def get_event(event_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    return await _event_detail(conn, event_id, viewer)


@router.post("/events", response_model=Event, status_code=201,
             summary="Create an event (Events moderator or admin); followers of its tags are alerted")
async def create_event(body: EventCreate, background: BackgroundTasks, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    if not await _is_moderator(conn, user):
        raise forbidden("Only Events moderators can add events. Ask one to post yours.")
    tag_ids = await _check_tags(conn, body.tag_ids)
    if body.poster_s3_key:
        await verify_own_uploads([body.poster_s3_key], "event_poster", user.id)
    notified, payload = [], {}
    async with conn.transaction():
        event_id = await conn.fetchval(
            """INSERT INTO events (created_by, title, description, location, start_time, end_time, poster_s3_key)
               VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id""",
            user.id, body.title, body.description or None, body.location or None, body.start_time, body.end_time,
            body.poster_s3_key or None)
        await conn.executemany("INSERT INTO event_tag_map (event_id, tag_id) VALUES ($1, $2)",
                               [(event_id, t) for t in tag_ids])
        if body.end_time >= datetime.now(timezone.utc):
            notified, payload = await _notify_followers(conn, event_id, body.title, body.start_time, tag_ids,
                                                        [user.id])
    background.add_task(deliver_push, notified, "followed_tag_event", payload)
    if body.poster_s3_key:
        await mark_attached([body.poster_s3_key])
    return await _event_detail(conn, event_id, user)


@router.patch("/events/{event_id}", response_model=Event,
              summary="Edit an event (organizer, events moderator or admin); people who bookmarked it are alerted")
async def update_event(event_id: UUID, body: EventUpdate, background: BackgroundTasks,
                       user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    changes = body.model_dump(exclude_unset=True)
    for required in ("title", "start_time", "end_time", "tag_ids"):
        if required in changes and changes[required] is None:
            raise HTTPException(422, f"{required} can't be empty.")
    new_tags = await _check_tags(conn, changes.pop("tag_ids")) if "tag_ids" in changes else None
    for optional in ("description", "location", "poster_s3_key"):
        if optional in changes:
            changes[optional] = changes[optional] or None
    if changes.get("poster_s3_key"):
        await verify_own_uploads([changes["poster_s3_key"]], "event_poster", user.id)
    old_poster = None
    alerts: list[tuple[list[UUID], str, dict]] = []
    async with conn.transaction():
        old = await _editable(conn, event_id, user)
        start, end = changes.get("start_time", old["start_time"]), changes.get("end_time", old["end_time"])
        if end <= start:
            raise HTTPException(422, "end_time must be after start_time.")
        if end - start > MAX_DURATION:
            raise HTTPException(422, "An event can last at most 30 days.")
        changes = {k: v for k, v in changes.items() if v != old[k]}
        if "poster_s3_key" in changes:
            old_poster = old["poster_s3_key"]
        if changes:
            sql, values = set_clause(changes, start=2)
            await conn.execute(f"UPDATE events SET {sql} WHERE id = $1", event_id, *values)
        added_tags: list[int] = []
        if new_tags is not None:
            old_tags = {r["tag_id"] for r in await conn.fetch(
                "SELECT tag_id FROM event_tag_map WHERE event_id = $1", event_id)}
            added_tags = [t for t in new_tags if t not in old_tags]
            await conn.execute("DELETE FROM event_tag_map WHERE event_id = $1 AND NOT (tag_id = ANY($2::int[]))",
                               event_id, new_tags)
            await conn.executemany("INSERT INTO event_tag_map (event_id, tag_id) VALUES ($1, $2)",
                                   [(event_id, t) for t in added_tags])
            if added_tags and not changes:
                await conn.execute("UPDATE events SET updated_at = now() WHERE id = $1", event_id)
        if old["created_by"] != user.id and (changes or new_tags is not None):
            await log_moderation(conn, user.id, "edit_event", "event", event_id)

        if end >= datetime.now(timezone.utc):
            title = changes.get("title", old["title"])
            what = []
            if "start_time" in changes or "end_time" in changes:
                what.append(f"now {_when_text(start)}")
            if "location" in changes:
                what.append(f"now at {changes['location']}" if changes["location"] else "place to be announced")
            if "title" in changes:
                what.append(f"renamed from “{old['title']}”")
            if "description" in changes and not what:
                what.append("details updated")
            bookmarkers = await _bookmarkers(conn, event_id, user.id) if what else []
            if bookmarkers:
                payload = {"event_id": str(event_id), "cancelled": False,
                           "message": f"“{title}” changed: {'; '.join(what)}"}
                alerts.append((await create_notifications(conn, bookmarkers, "bookmarked_event_update", payload),
                               "bookmarked_event_update", payload))
            if added_tags:
                notified, payload = await _notify_followers(conn, event_id, title, start, added_tags,
                                                            [user.id, old["created_by"], *bookmarkers])
                alerts.append((notified, "followed_tag_event", payload))
    for notified, kind, payload in alerts:
        background.add_task(deliver_push, notified, kind, payload)
    if changes.get("poster_s3_key"):
        await mark_attached([changes["poster_s3_key"]])
    if old_poster:
        background.add_task(delete_objects, [old_poster])
    return await _event_detail(conn, event_id, user)


@router.delete("/events/{event_id}", status_code=204,
               summary="Cancel (remove) an event (organizer, events moderator or admin); people who bookmarked it are alerted")
async def delete_event(event_id: UUID, background: BackgroundTasks, reason: str | None = Query(None, max_length=500),
                       user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    notified, payload = [], {}
    async with conn.transaction():
        old = await _editable(conn, event_id, user)
        await conn.execute("UPDATE events SET deleted_at = now(), deleted_by = $2 WHERE id = $1", event_id, user.id)
        if old["created_by"] != user.id:
            await log_moderation(conn, user.id, "remove_event", "event", event_id, reason)
        if old["end_time"] >= datetime.now(timezone.utc):
            payload = {"event_id": str(event_id), "cancelled": True, "message": f"“{old['title']}” was cancelled."}
            notified = await create_notifications(conn, await _bookmarkers(conn, event_id, user.id),
                                                  "bookmarked_event_update", payload)
        await conn.execute("DELETE FROM bookmarks WHERE target_type = 'event' AND target_id = $1", event_id)
    background.add_task(deliver_push, notified, "bookmarked_event_update", payload)
    return Response(status_code=204)


# ---------------------------------------------------------------- bookmarks
_TARGET_TABLE = {"listing": "listings", "event": "events"}


async def _target_exists(conn: asyncpg.Connection, target_type: str, target_id: UUID) -> bool:
    return await conn.fetchval(
        f"SELECT EXISTS (SELECT 1 FROM {_TARGET_TABLE[target_type]} WHERE id = $1 AND deleted_at IS NULL)", target_id)


@router.get("/me/bookmarks", response_model=list[Bookmark], summary="My bookmarks, newest first")
async def list_bookmarks(target_type: BookmarkTarget | None = None, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(
        """SELECT b.target_type::text AS target_type, b.target_id, b.created_at FROM bookmarks b
           LEFT JOIN listings l ON b.target_type = 'listing' AND l.id = b.target_id
           LEFT JOIN events e ON b.target_type = 'event' AND e.id = b.target_id
           WHERE b.user_id = $1 AND ($2::text IS NULL OR b.target_type::text = $2)
             AND coalesce(l.deleted_at, e.deleted_at) IS NULL AND coalesce(l.id, e.id) IS NOT NULL
           ORDER BY b.created_at DESC, b.target_id LIMIT 1000""", user.id, target_type)
    return [Bookmark(**dict(r)) for r in rows]


@router.put("/me/bookmarks/{target_type}/{target_id}", response_model=Bookmark,
            summary="Bookmark a listing or event (saving it twice is fine)")
async def add_bookmark(target_type: BookmarkTarget, target_id: UUID, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    if not await _target_exists(conn, target_type, target_id):
        raise not_found("Listing" if target_type == "listing" else "Event")
    await conn.execute(
        "INSERT INTO bookmarks (user_id, target_type, target_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
        user.id, target_type, target_id)
    created_at = await conn.fetchval(
        "SELECT created_at FROM bookmarks WHERE user_id = $1 AND target_type = $2 AND target_id = $3",
        user.id, target_type, target_id)
    return Bookmark(target_type=target_type, target_id=target_id, created_at=created_at)


@router.delete("/me/bookmarks/{target_type}/{target_id}", status_code=204, summary="Remove a bookmark")
async def remove_bookmark(target_type: BookmarkTarget, target_id: UUID, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    await conn.execute("DELETE FROM bookmarks WHERE user_id = $1 AND target_type = $2 AND target_id = $3",
                       user.id, target_type, target_id)
    return Response(status_code=204)


@router.post("/me/bookmarks/import", response_model=BookmarkImportResult,
             summary="Save the bookmarks a guest kept on this device to the account (after sign-in)")
async def import_bookmarks(body: BookmarkImport, user: CurrentUser = Depends(current_user),
                           conn: asyncpg.Connection = Depends(get_conn)):
    added = already = skipped = 0
    async with conn.transaction():
        for item in {(i.target_type, i.target_id) for i in body.items}:
            if not await _target_exists(conn, *item):
                skipped += 1
                continue
            inserted = await conn.fetchval(
                """INSERT INTO bookmarks (user_id, target_type, target_id) VALUES ($1, $2, $3)
                   ON CONFLICT DO NOTHING RETURNING true""", user.id, *item)
            if inserted:
                added += 1
            else:
                already += 1
    return BookmarkImportResult(added=added, already_saved=already, skipped=skipped)
