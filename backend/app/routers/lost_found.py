"""Lost & Found reports (FR-7, FR-8, FR-9, FR-10).

Lost reports and found reports work the same way, so one factory builds both routers:
  /lost-reports   and   /found-reports

Matching (FR-9): the category says what the item is ("ID card"). When someone files a
found report, every open lost report in the same category, lost no later than the
item was found, by someone else, gets an in-app notification plus a push.
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import AfterValidator, BaseModel, Field

from ..auth import CurrentUser, current_user, optional_user
from ..common import (CategoryRef, Contact, Page, PageParams, Photo, UserRef, forbidden, make_page,
                      not_found, page_params, set_clause)
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import is_module_moderator, log_moderation
from ..storage import delete_objects, file_url, verify_own_uploads
from .listings import PhotoKeys

ReportStatus = Literal["open", "matched", "closed"]


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
    description: str = Field(min_length=1, max_length=2000)
    category_id: int = Field(description="What the item is, e.g. the id of 'ID card'")
    occurred_at: PastTime = Field(description="When the item was lost (lost reports) or found (found reports)")
    location: str | None = Field(None, max_length=200)
    photo_keys: PhotoKeys = Field(default_factory=list)


class ReportUpdate(BaseModel):
    description: str | None = Field(None, min_length=1, max_length=2000)
    category_id: int | None = None
    occurred_at: PastTime | None = None
    location: str | None = Field(None, max_length=200)


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
           (SELECT p.s3_key FROM {k.photos} p WHERE p.{k.photo_fk} = r.id
            ORDER BY p.sort_order LIMIT 1) AS cover_key
    FROM {k.table} r
    JOIN lf_categories c ON c.id = r.category_id
    JOIN users u ON u.id = r.reporter_id
    """


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
            reporter_contact=Contact(email=r["reporter_email"], phone=r["reporter_phone"]) if viewer else None,
            updated_at=r["updated_at"])

    async def owned(conn: asyncpg.Connection, report_id: UUID, user: CurrentUser) -> None:
        reporter = await conn.fetchval(
            f"SELECT reporter_id FROM {kind.table} WHERE id = $1 AND deleted_at IS NULL", report_id)
        if reporter is None:
            raise not_found(f"{kind.name.capitalize()} report")
        if reporter != user.id:
            raise forbidden("Only the person who filed this report can change it.")

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
            ORDER BY r.created_at DESC LIMIT 10""", category_id, when, user_id)
        return [summary(r, other) for r in rows]

    @router.get("", response_model=Page[ReportSummary], summary=f"Browse {kind.name} reports (guests allowed)")
    async def list_reports(
        category_id: int | None = None,
        status: list[ReportStatus] | None = Query(None),
        q: str | None = Query(None, max_length=200, description="Words in the description"),
        reporter_id: UUID | None = None,
        page: PageParams = Depends(page_params),
        conn: asyncpg.Connection = Depends(get_conn),
    ):
        rows = await conn.fetch(
            select + """
            WHERE r.deleted_at IS NULL
              AND ($1::int IS NULL OR r.category_id = $1)
              AND ($2::text[] IS NULL OR r.status::text = ANY($2::text[]))
              AND ($3::text IS NULL OR r.description ILIKE '%' || $3 || '%')
              AND ($4::uuid IS NULL OR r.reporter_id = $4)
            ORDER BY r.created_at DESC, r.id DESC
            LIMIT $5 OFFSET $6""",
            category_id, status, q, reporter_id, page.limit + 1, page.offset)
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
        payload: dict = {}
        async with conn.transaction():
            report_id = await conn.fetchval(
                f"""INSERT INTO {kind.table} (reporter_id, description, category_id, {kind.when}, location)
                    VALUES ($1, $2, $3, $4, $5) RETURNING id""",
                user.id, body.description, body.category_id, body.occurred_at, body.location)
            await insert_photos(conn, report_id, body.photo_keys)
            if kind is FOUND:
                # FR-9: tell everyone who lost this kind of item.
                lost = await conn.fetch(
                    """SELECT l.reporter_id, array_agg(l.id) AS lost_report_ids, c.name AS category
                       FROM lost_reports l JOIN lf_categories c ON c.id = l.category_id
                       WHERE l.category_id = $1 AND l.status = 'open' AND l.deleted_at IS NULL
                         AND l.lost_at <= $2 AND l.reporter_id <> $3
                       GROUP BY l.reporter_id, c.name""",
                    body.category_id, body.occurred_at, user.id)
                for row in lost:
                    payload = {"found_report_id": str(report_id),
                               "lost_report_ids": [str(i) for i in row["lost_report_ids"]],
                               "message": f"Someone found a {row['category']}. Check if it's yours."}
                    notified += await create_notifications(conn, [row["reporter_id"]], "lost_found_match", payload)
        if notified:
            background.add_task(deliver_push, notified, "lost_found_match",
                                {"found_report_id": str(report_id), "message": payload["message"]})
        result = await detail(conn, report_id, user)
        result.possible_matches = await possible_matches(conn, body.category_id, body.occurred_at, user.id)
        return result

    @router.patch("/{report_id}", response_model=ReportDetail, summary="Edit a report (reporter only)")
    async def update_report(report_id: UUID, body: ReportUpdate, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
        await owned(conn, report_id, user)
        changes = body.model_dump(exclude_unset=True)
        for required in ("description", "category_id", "occurred_at"):
            if required in changes and changes[required] is None:
                raise HTTPException(422, f"{required} can't be empty.")
        if "occurred_at" in changes:
            changes[kind.when] = changes.pop("occurred_at")
        sql, values = set_clause(changes, start=2)
        await conn.execute(f"UPDATE {kind.table} SET {sql} WHERE id = $1", report_id, *values)
        return await detail(conn, report_id, user)

    @router.patch("/{report_id}/status", response_model=ReportDetail,
                  summary="Mark open / matched / closed (reporter only)")
    async def update_status(report_id: UUID, body: StatusUpdate, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
        await owned(conn, report_id, user)
        await conn.execute(f"UPDATE {kind.table} SET status = $2 WHERE id = $1", report_id, body.status)
        return await detail(conn, report_id, user)

    @router.put("/{report_id}/photos", response_model=ReportDetail, summary="Replace the photo list (reporter only)")
    async def replace_photos(report_id: UUID, body: PhotosUpdate, background: BackgroundTasks,
                             user: CurrentUser = Depends(current_user),
                             conn: asyncpg.Connection = Depends(get_conn)):
        await owned(conn, report_id, user)
        old_keys = {r["s3_key"] for r in await conn.fetch(
            f"SELECT s3_key FROM {kind.photos} WHERE {kind.photo_fk} = $1", report_id)}
        await verify_own_uploads([k for k in body.photo_keys if k not in old_keys], kind.upload_kind, user.id)
        async with conn.transaction():
            await conn.execute(f"DELETE FROM {kind.photos} WHERE {kind.photo_fk} = $1", report_id)
            await insert_photos(conn, report_id, body.photo_keys)
            await conn.execute(f"UPDATE {kind.table} SET updated_at = now() WHERE id = $1", report_id)
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
            if not is_owner:
                await log_moderation(conn, user.id, f"remove_{kind.name}_report", f"{kind.name}_report",
                                     report_id, reason)
        return Response(status_code=204)

    return router


lost_router = build_router(LOST)
found_router = build_router(FOUND)
