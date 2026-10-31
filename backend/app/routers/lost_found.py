"""Lost & Found reports (FR-7, FR-8, FR-9, FR-10).

Lost reports and found reports work the same way, so one factory builds both routers:
  /lost-reports   and   /found-reports

Matching (FR-9): the category says what the item is ("ID card"). When someone files a
found report, every open lost report in the same category, lost no later than the
item was found, by someone else, gets an in-app notification plus a push. Matching runs
again when a found report's category or time is edited, or it is reopened; nobody is told
twice about the same found report. A found report also alerts matching saved Lost & Found
searches (app/alerts.py).
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import AfterValidator, BaseModel, Field

from ..alerts import found_report_alerts, push_alerts
from ..auth import CurrentUser, current_user, optional_user
from ..common import (MAX_INT_ID, CategoryId, CategoryRef, Contact, Page, PageParams, Photo, UserRef, forbidden,
                      make_page, not_found, page_params, search_text, set_clause, text)
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import close_reports, is_module_moderator, log_moderation
from ..storage import delete_objects, file_url, mark_attached, verify_own_uploads
from .listings import PhotoKeys

# "matched" was dropped (rev 11): a report is open until its owner closes it.
ReportStatus = Literal["open", "closed"]


@dataclass(frozen=True)
class Kind:
    name: str          # "lost" or "found"
    table: str         # lost_reports
    photos: str        # lost_report_photos
    photo_fk: str      # lost_report_id
    when: str          # lost_at
    upload_kind: str   # lost_report_photo


LOST = Kind("lost", "lost_reports", "lost_report_photos", "lost_report_id", "lost_at", "lost_report_photo")
FOUND = Kind("found", "found_reports", "found_report_photos", "found_report_id", "found_at", "found_report_photo")


def _not_in_future(value: datetime | None) -> datetime | None:
    if value is None:
        return value
    if value.tzinfo is None:
        raise ValueError("include a timezone, e.g. 2026-10-20T14:30:00+05:30")
    if value > datetime.now(timezone.utc) + timedelta(minutes=5):
        raise ValueError("can't be in the future")
    return value


PastTime = Annotated[datetime, AfterValidator(_not_in_future)]


class ReportCreate(BaseModel):
    description: text(2000)
    category_id: CategoryId = Field(description="What the item is, e.g. the id of 'ID card'")
    occurred_at: PastTime = Field(description="When the item was lost (lost reports) or found (found reports)")
    location: text(200, min_length=0) | None = None
    photo_keys: PhotoKeys = Field(default_factory=list)


class ReportUpdate(BaseModel):
    description: text(2000) | None = None
    category_id: CategoryId | None = None
    occurred_at: PastTime | None = None
    location: text(200, min_length=0) | None = None


class StatusUpdate(BaseModel):
    status: ReportStatus


class PhotosUpdate(BaseModel):
    photo_keys: PhotoKeys


class ReportSummary(BaseModel):
    id: UUID
    kind: Literal["lost", "found"]
    description: str
    category: CategoryRef
    occurred_at: datetime
    location: str | None
    status: ReportStatus
    reporter: UserRef
    cover_photo_url: str | None
    created_at: datetime


class ReportDetail(ReportSummary):
    photos: list[Photo]
    reporter_contact: Contact | None = Field(description="Shown to signed-in users only")
    updated_at: datetime
    possible_matches: list[ReportSummary] | None = Field(
        None, description="Only on create: open reports of the other kind in the same category")


def select_for(k: Kind) -> str:
    return f"""
    SELECT r.id, r.description, r.{k.when} AS occurred_at, r.location, r.status::text AS status,
           r.created_at, r.updated_at, r.reporter_id,
           c.id AS category_id, c.name AS category_name,
           u.name AS reporter_name, u.email::text AS reporter_email, u.phone AS reporter_phone,
           u.is_active AS reporter_active,
           (SELECT p.s3_key FROM {k.photos} p WHERE p.{k.photo_fk} = r.id
            ORDER BY p.sort_order LIMIT 1) AS cover_key
    FROM {k.table} r
    JOIN lf_categories c ON c.id = r.category_id
    JOIN users u ON u.id = r.reporter_id
    """


def _like_pattern(q: str) -> str:
    """Escape LIKE wildcards so a search for "50%" or "u_b" matches those characters literally."""
    return q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


async def notify_lost_reporters(conn: asyncpg.Connection, found_report_id: UUID, category_id: int,
                                found_at: datetime, finder_id: UUID) -> tuple[list[UUID], str | None]:
    """FR-9: tell everyone with a matching open lost report, unless they were already told about
    this found report. Returns the users notified and the message."""
    lost = await conn.fetch(
        """SELECT l.reporter_id, array_agg(l.id) AS lost_report_ids, c.name AS category
           FROM lost_reports l JOIN lf_categories c ON c.id = l.category_id
           WHERE l.category_id = $1 AND l.status = 'open' AND l.deleted_at IS NULL
             AND l.lost_at <= $2 AND l.reporter_id <> $3
             AND NOT EXISTS (SELECT 1 FROM notifications n
                             WHERE n.user_id = l.reporter_id AND n.type = 'lost_found_match'
                               AND n.payload->>'found_report_id' = $4)
           GROUP BY l.reporter_id, c.name""",
        category_id, found_at, finder_id, str(found_report_id))
    notified: list[UUID] = []
    message = None
    for row in lost:
        message = f"Someone found a {row['category']}. Check if it's yours."
        payload = {"found_report_id": str(found_report_id),
                   "lost_report_ids": [str(i) for i in row["lost_report_ids"]], "message": message}
        notified += await create_notifications(conn, [row["reporter_id"]], "lost_found_match", payload)
    return notified, message


def build_router(kind: Kind) -> APIRouter:
    other = FOUND if kind is LOST else LOST
    router = APIRouter(prefix=f"/{kind.name}-reports", tags=["Lost & Found"])

    select = select_for(kind)

    def summary(r: asyncpg.Record, k: Kind = kind) -> ReportSummary:
        return ReportSummary(
            id=r["id"], kind=k.name, description=r["description"],
            category=CategoryRef(id=r["category_id"], name=r["category_name"]),
            occurred_at=r["occurred_at"], location=r["location"], status=r["status"],
            reporter=UserRef(id=r["reporter_id"], name=r["reporter_name"]),
            cover_photo_url=file_url(r["cover_key"]) if r["cover_key"] else None,
            created_at=r["created_at"])

    async def detail(conn: asyncpg.Connection, report_id: UUID, viewer: CurrentUser | None) -> ReportDetail:
        r = await conn.fetchrow(select + " WHERE r.id = $1 AND r.deleted_at IS NULL", report_id)
        if r is None:
            raise not_found(f"{kind.name.capitalize()} report")
        photos = await conn.fetch(
            f"SELECT s3_key, sort_order FROM {kind.photos} WHERE {kind.photo_fk} = $1 ORDER BY sort_order",
            report_id)
        return ReportDetail(
            **summary(r).model_dump(),
            photos=[Photo(s3_key=p["s3_key"], url=file_url(p["s3_key"]), sort_order=p["sort_order"])
                    for p in photos],
            reporter_contact=(Contact(email=r["reporter_email"], phone=r["reporter_phone"])
                              if viewer and r["reporter_active"] else None),
            updated_at=r["updated_at"])

    async def editable(conn: asyncpg.Connection, report_id: UUID, user: CurrentUser) -> asyncpg.Record:
        """The reporter or an admin may change a report; `by_admin` is True when an admin edits someone else's."""
        row = await conn.fetchrow(
            f"""SELECT reporter_id, category_id, {kind.when} AS occurred_at, status::text AS status,
                       reporter_id <> $2 AS by_admin
                FROM {kind.table} WHERE id = $1 AND deleted_at IS NULL""", report_id, user.id)
        if row is None:
            raise not_found(f"{kind.name.capitalize()} report")
        if row["by_admin"] and not user.is_admin:
            raise forbidden("Only the person who filed this report can change it.")
        return row

    async def rematch(conn: asyncpg.Connection, report_id: UUID, background: BackgroundTasks) -> None:
        """Run FR-9 matching and saved-search alerts again for a found report that changed or reopened."""
        r = await conn.fetchrow(
            f"""SELECT category_id, {kind.when} AS occurred_at, reporter_id FROM {kind.table}
                WHERE id = $1 AND status = 'open' AND deleted_at IS NULL""", report_id)
        if r is None:
            return
        notified, message = await notify_lost_reporters(conn, report_id, r["category_id"], r["occurred_at"],
                                                        r["reporter_id"])
        if notified:
            background.add_task(deliver_push, notified, "lost_found_match",
                                {"found_report_id": str(report_id), "message": message})
        push_alerts(background, await found_report_alerts(conn, report_id))

    async def insert_photos(conn: asyncpg.Connection, report_id: UUID, keys: list[str]) -> None:
        await conn.executemany(
            f"INSERT INTO {kind.photos} ({kind.photo_fk}, s3_key, sort_order) VALUES ($1, $2, $3)",
            [(report_id, key, i) for i, key in enumerate(keys, start=1)])

    async def possible_matches(conn: asyncpg.Connection, category_id: int, when: datetime,
                               user_id: UUID) -> list[ReportSummary]:
        """Open reports of the other kind, same category, by someone else, with compatible times."""
        time_rule = f"r.{other.when} >= $2" if kind is LOST else f"r.{other.when} <= $2"
        rows = await conn.fetch(
            select_for(other) + f"""
            WHERE r.category_id = $1 AND {time_rule} AND r.reporter_id <> $3
              AND r.status = 'open' AND r.deleted_at IS NULL
            ORDER BY r.created_at DESC, r.id DESC LIMIT 10""", category_id, when, user_id)
        return [summary(r, other) for r in rows]

    @router.get("", response_model=Page[ReportSummary], summary=f"Browse {kind.name} reports (guests allowed)")
    async def list_reports(
        category_id: int | None = Query(None, ge=1, le=MAX_INT_ID),
        status: list[ReportStatus] | None = Query(None),
        q: str | None = Query(None, max_length=200, description="Words in the description"),
        reporter_id: UUID | None = None,
        from_date: datetime | None = Query(None, description=f"Only items {kind.name} at or after this time"),
        to_date: datetime | None = Query(None, description=f"Only items {kind.name} at or before this time"),
        sort: Literal["newest", "oldest"] = Query("newest", description="By when the report was filed"),
        page: PageParams = Depends(page_params),
        conn: asyncpg.Connection = Depends(get_conn),
    ):
        order = "r.created_at DESC, r.id DESC" if sort == "newest" else "r.created_at ASC, r.id ASC"
        rows = await conn.fetch(
            select + f"""
            WHERE r.deleted_at IS NULL
              AND ($1::int IS NULL OR r.category_id = $1)
              AND ($2::text[] IS NULL OR r.status::text = ANY($2::text[]))
              AND ($3::text IS NULL OR r.description ILIKE '%' || $3 || '%' ESCAPE '\\')
              AND ($4::uuid IS NULL OR r.reporter_id = $4)
              AND ($7::timestamptz IS NULL OR r.{kind.when} >= $7)
              AND ($8::timestamptz IS NULL OR r.{kind.when} <= $8)
            ORDER BY {order}
            LIMIT $5 OFFSET $6""",
            category_id, status, _like_pattern(q) if (q := search_text(q)) else None, reporter_id,
            page.limit + 1, page.offset, from_date, to_date)
        return make_page(rows, page, summary)

    @router.get("/{report_id}", response_model=ReportDetail, summary=f"One {kind.name} report")
    async def get_report(report_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
        return await detail(conn, report_id, viewer)

    @router.post("", response_model=ReportDetail, status_code=201, summary=f"File a {kind.name} report")
    async def create_report(body: ReportCreate, background: BackgroundTasks,
                            user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
        await verify_own_uploads(body.photo_keys, kind.upload_kind, user.id)
        notified: list[UUID] = []
        message = None
        pushes = []
        async with conn.transaction():
            report_id = await conn.fetchval(
                f"""INSERT INTO {kind.table} (reporter_id, description, category_id, {kind.when}, location)
                    VALUES ($1, $2, $3, $4, $5) RETURNING id""",
                user.id, body.description, body.category_id, body.occurred_at, body.location)
            await insert_photos(conn, report_id, body.photo_keys)
            if kind is FOUND:
                # FR-9: tell everyone who lost this kind of item.
                notified, message = await notify_lost_reporters(conn, report_id, body.category_id,
                                                                body.occurred_at, user.id)
                pushes = await found_report_alerts(conn, report_id)
        await mark_attached(body.photo_keys)
        if notified:
            background.add_task(deliver_push, notified, "lost_found_match",
                                {"found_report_id": str(report_id), "message": message})
        push_alerts(background, pushes)
        result = await detail(conn, report_id, user)
        result.possible_matches = await possible_matches(conn, body.category_id, body.occurred_at, user.id)
        return result

    @router.patch("/{report_id}", response_model=ReportDetail, summary="Edit a report (reporter or admin)")
    async def update_report(report_id: UUID, body: ReportUpdate, background: BackgroundTasks,
                            user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
        before = await editable(conn, report_id, user)
        changes = body.model_dump(exclude_unset=True)
        for required in ("description", "category_id", "occurred_at"):
            if required in changes and changes[required] is None:
                raise HTTPException(422, f"{required} can't be empty.")
        # A new description can match saved keyword searches too (each person is still told once).
        rematch_needed = kind is FOUND and (
            changes.get("category_id", before["category_id"]) != before["category_id"]
            or changes.get("occurred_at", before["occurred_at"]) != before["occurred_at"]
            or "description" in changes)
        if "occurred_at" in changes:
            changes[kind.when] = changes.pop("occurred_at")
        sql, values = set_clause(changes, start=2)
        async with conn.transaction():
            await conn.execute(f"UPDATE {kind.table} SET {sql} WHERE id = $1", report_id, *values)
            if before["by_admin"]:
                await log_moderation(conn, user.id, f"edit_{kind.name}_report", f"{kind.name}_report", report_id)
            if rematch_needed:
                await rematch(conn, report_id, background)
        return await detail(conn, report_id, user)

    @router.patch("/{report_id}/status", response_model=ReportDetail,
                  summary="Mark open / closed (reporter or admin)")
    async def update_status(report_id: UUID, body: StatusUpdate, background: BackgroundTasks,
                            user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
        before = await editable(conn, report_id, user)
        async with conn.transaction():
            await conn.execute(f"UPDATE {kind.table} SET status = $2 WHERE id = $1", report_id, body.status)
            if before["by_admin"]:
                await log_moderation(conn, user.id, f"change_{kind.name}_report_status", f"{kind.name}_report",
                                     report_id, body.status)
            if kind is FOUND and body.status == "open" and before["status"] != "open":
                await rematch(conn, report_id, background)
        return await detail(conn, report_id, user)

    @router.put("/{report_id}/photos", response_model=ReportDetail,
                summary="Replace the photo list (reporter or admin)")
    async def replace_photos(report_id: UUID, body: PhotosUpdate, background: BackgroundTasks,
                             user: CurrentUser = Depends(current_user),
                             conn: asyncpg.Connection = Depends(get_conn)):
        before = await editable(conn, report_id, user)
        old_keys = {r["s3_key"] for r in await conn.fetch(
            f"SELECT s3_key FROM {kind.photos} WHERE {kind.photo_fk} = $1", report_id)}
        new_keys = [k for k in body.photo_keys if k not in old_keys]
        await verify_own_uploads(new_keys, kind.upload_kind, user.id)
        async with conn.transaction():
            await conn.execute(f"DELETE FROM {kind.photos} WHERE {kind.photo_fk} = $1", report_id)
            await insert_photos(conn, report_id, body.photo_keys)
            await conn.execute(f"UPDATE {kind.table} SET updated_at = now() WHERE id = $1", report_id)
            if before["by_admin"]:
                await log_moderation(conn, user.id, f"replace_{kind.name}_report_photos", f"{kind.name}_report",
                                     report_id)
        await mark_attached(new_keys)
        background.add_task(delete_objects, sorted(old_keys - set(body.photo_keys)))
        return await detail(conn, report_id, user)

    @router.delete("/{report_id}", status_code=204,
                   summary="Remove a report (reporter, Lost & Found moderator or admin; FR-10)")
    async def delete_report(report_id: UUID, reason: str | None = Query(None, max_length=500),
                            user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
        reporter = await conn.fetchval(
            f"SELECT reporter_id FROM {kind.table} WHERE id = $1 AND deleted_at IS NULL", report_id)
        if reporter is None:
            raise not_found(f"{kind.name.capitalize()} report")
        is_owner = reporter == user.id
        if not is_owner and not await is_module_moderator(conn, user, "lost_found"):
            raise forbidden("Only the reporter or a Lost & Found moderator can remove this report.")
        async with conn.transaction():
            await conn.execute(f"UPDATE {kind.table} SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                               report_id, user.id)
            await close_reports(conn, f"{kind.name}_report", [report_id], user.id, reason)
            if not is_owner:
                await log_moderation(conn, user.id, f"remove_{kind.name}_report", f"{kind.name}_report",
                                     report_id, reason)
        return Response(status_code=204)

    return router


lost_router = build_router(LOST)
found_router = build_router(FOUND)
