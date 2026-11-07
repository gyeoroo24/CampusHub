"""Lost & Found reports (FR-7, FR-8, FR-9, FR-10).

Lost reports and found reports work the same way, so one factory builds both routers:
  /lost-reports   and   /found-reports

Matching (FR-9, future plan §1.2): when the matcher is available (app/matching), every new,
edited or reopened report, or one with new photos, is compared by description and photo with
open reports of the other kind, in any category. Likely pairs are stored and shown to the
report's owner (GET /{kind}-reports/{id}/matches); a strong one alerts the lost report's owner.
Without it (match_mode "off") the old rule applies: a found report alerts every open lost report
in the same category, lost no later than the item was found, by someone else. Either way nobody
is told twice about the same found report. A found report also alerts matching saved Lost &
Found searches (app/alerts.py).
"""
from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import AfterValidator, BaseModel, Field

from .. import cache
from ..alerts import found_report_alerts, push_alerts
from ..auth import CurrentUser, current_user, optional_user
from ..common import (MAX_INT_ID, CategoryId, CategoryRef, Contact, Page, PageParams, Photo, UserRef, forbidden,
                      like_pattern, make_page, not_found, page_params, search_text, set_clause, text)
from ..db import get_conn
from ..lf_kinds import FOUND, LOST, Kind, other_kind
from ..matching.trigger import match_mode, request_match, request_photo_screen, strength
from ..screening import screen_text
from ..notify import create_notifications, deliver_push
from ..permissions import close_reports, is_module_moderator, log_moderation
from ..storage import delete_objects, file_url, mark_attached, verify_own_uploads
from .listings import PhotoKeys

# "matched" was dropped (rev 11): a report is open until its owner closes it.
ReportStatus = Literal["open", "closed"]


# The app's date picker starts here too (report_item_dialog.dart); anything earlier is a typo like year 0026.
EARLIEST_OCCURRED_AT = datetime(2020, 1, 1, tzinfo=timezone.utc)


def _not_in_future(value: datetime | None) -> datetime | None:
    if value is None:
        return value
    if value.tzinfo is None:
        raise ValueError("include a timezone, e.g. 2026-10-20T14:30:00+05:30")
    if value > datetime.now(timezone.utc) + timedelta(minutes=5):
        raise ValueError("can't be in the future")
    if value < EARLIEST_OCCURRED_AT:
        raise ValueError("can't be before 2020")
    return value


PastTime = Annotated[datetime, AfterValidator(_not_in_future)]


class ReportCreate(BaseModel):
    title: text(120, single_line=True) | None = Field(None, description="Short name of the item, e.g. 'Black JBL earbuds' (rev 25)")
    description: text(2000)
    category_id: CategoryId = Field(description="What the item is, e.g. the id of 'ID card'")
    occurred_at: PastTime = Field(description="When the item was lost (lost reports) or found (found reports)")
    location: text(200, min_length=0) | None = None
    photo_keys: PhotoKeys = Field(default_factory=list)


class ReportUpdate(BaseModel):
    title: text(120, single_line=True) | None = None
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
    title: str | None = Field(description="null on reports filed before titles existed")
    description: str
    category: CategoryRef
    occurred_at: datetime
    location: str | None
    status: ReportStatus
    reporter: UserRef
    reporter_deactivated: bool = Field(False, description="The reporter has deactivated their account")
    cover_photo_url: str | None
    created_at: datetime


class ReportDetail(ReportSummary):
    photos: list[Photo]
    reporter_contact: Contact | None = Field(description="Shown to signed-in users only")
    updated_at: datetime
    possible_matches: list[ReportSummary] | None = Field(
        None, description="Only on create: open reports of the other kind in the same category. "
                          "The ranked list is GET /{kind}-reports/{id}/matches.")


class PossibleMatch(BaseModel):
    report: ReportSummary
    score: float | None = Field(description="0-1; null when ranking is unavailable")
    strength: Literal["strong", "possible"] | None
    reasons: list[str] = Field(description='e.g. "Similar description", "Similar photo"')


class MatchList(BaseModel):
    status: Literal["ready", "pending", "unavailable"] = Field(
        description="pending: still being matched, ask again shortly; "
                    "unavailable: no matcher, so the list is same-category reports, unranked")
    matches: list[PossibleMatch]


def select_for(k: Kind, extra_columns: str = "") -> str:
    return f"""
    SELECT {extra_columns}r.id, r.title, r.description, r.{k.when} AS occurred_at, r.location, r.status::text AS status,
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
    other = other_kind(kind)
    router = APIRouter(prefix=f"/{kind.name}-reports", tags=["Lost & Found"])

    select = select_for(kind)

    def summary(r: asyncpg.Record, k: Kind = kind) -> ReportSummary:
        return ReportSummary(
            id=r["id"], kind=k.name, title=r["title"], description=r["description"],
            category=CategoryRef(id=r["category_id"], name=r["category_name"]),
            occurred_at=r["occurred_at"], location=r["location"], status=r["status"],
            reporter=UserRef(id=r["reporter_id"], name=r["reporter_name"]),
            reporter_deactivated=not r["reporter_active"],
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
        """Only the reporter may change a report. Moderators and the admin can remove it (DELETE), not edit it."""
        row = await conn.fetchrow(
            f"""SELECT reporter_id, category_id, {kind.when} AS occurred_at, status::text AS status
                FROM {kind.table} WHERE id = $1 AND deleted_at IS NULL""", report_id)
        if row is None:
            raise not_found(f"{kind.name.capitalize()} report")
        if row["reporter_id"] != user.id:
            raise forbidden("Only the person who filed this report can change it.")
        return row

    async def rematch(conn: asyncpg.Connection, report_id: UUID, background: BackgroundTasks) -> None:
        """Saved-search alerts again for a found report that changed or reopened, plus the old FR-9
        category rule when there's no matcher (the matcher is started by the caller)."""
        r = await conn.fetchrow(
            f"""SELECT category_id, {kind.when} AS occurred_at, reporter_id FROM {kind.table}
                WHERE id = $1 AND status = 'open' AND deleted_at IS NULL""", report_id)
        if r is None:
            return
        if match_mode() == "off":
            notified, message = await notify_lost_reporters(conn, report_id, r["category_id"], r["occurred_at"],
                                                            r["reporter_id"])
            if notified:
                background.add_task(deliver_push, notified, "lost_found_match",
                                    {"found_report_id": str(report_id), "message": message})
        push_alerts(background, await found_report_alerts(conn, report_id))

    async def needs_rematch(conn: asyncpg.Connection, report_id: UUID) -> None:
        """What matching looks at changed: the matcher's last result is out of date."""
        await conn.execute(f"UPDATE {kind.table} SET match_rev = match_rev + 1 WHERE id = $1", report_id)

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
        q: str | None = Query(None, max_length=200, description="Words in the title or description"),
        reporter_id: UUID | None = None,
        from_date: datetime | None = Query(None, description=f"Only items {kind.name} at or after this time"),
        to_date: datetime | None = Query(None, description=f"Only items {kind.name} at or before this time"),
        sort: Literal["newest", "oldest"] = Query("newest", description="By when the report was filed"),
        page: PageParams = Depends(page_params),
        conn: asyncpg.Connection = Depends(get_conn),
    ):
        search = search_text(q)

        async def _fetch():
            order = "r.created_at DESC, r.id DESC" if sort == "newest" else "r.created_at ASC, r.id ASC"
            rows = await conn.fetch(
                select + f"""
                WHERE r.deleted_at IS NULL
                  AND ($1::int IS NULL OR r.category_id = $1)
                  AND ($2::text[] IS NULL OR r.status::text = ANY($2::text[]))
                  AND ($3::text IS NULL OR r.description ILIKE '%' || $3 || '%' ESCAPE '\\'
                       OR r.title ILIKE '%' || $3 || '%' ESCAPE '\\')
                  AND ($4::uuid IS NULL OR r.reporter_id = $4)
                  AND ($7::timestamptz IS NULL OR r.{kind.when} >= $7)
                  AND ($8::timestamptz IS NULL OR r.{kind.when} <= $8)
                ORDER BY {order}
                LIMIT $5 OFFSET $6""",
                category_id, status, like_pattern(search) if search else None, reporter_id,
                page.limit + 1, page.offset, from_date, to_date)
            return make_page(rows, page, summary)

        # Not viewer-scoped: this listing doesn't depend on who's asking (no optional_user/current_user
        # dependency above), so one cache entry safely covers every caller for a given filter set.
        key = cache.build_key(f"lost-found:{kind.name}", None, category_id, status, q, reporter_id,
                              from_date, to_date, sort, page.limit, page.offset)
        return await cache.get_or_set(key, None, _fetch)

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
                f"""INSERT INTO {kind.table} (reporter_id, title, description, category_id, {kind.when}, location)
                    VALUES ($1, $2, $3, $4, $5, $6) RETURNING id""",
                user.id, body.title, body.description, body.category_id, body.occurred_at, body.location)
            await insert_photos(conn, report_id, body.photo_keys)
            await screen_text(conn, background, f"{kind.name}_report", report_id)   # automatic flagging, §1.6
            if kind is FOUND:
                if match_mode() == "off":
                    # FR-9 without the matcher: tell everyone who lost this kind of item.
                    notified, message = await notify_lost_reporters(conn, report_id, body.category_id,
                                                                    body.occurred_at, user.id)
                pushes = await found_report_alerts(conn, report_id)
        await mark_attached(body.photo_keys)
        if notified:
            background.add_task(deliver_push, notified, "lost_found_match",
                                {"found_report_id": str(report_id), "message": message})
        push_alerts(background, pushes)
        request_match(background, kind.name, report_id)
        if body.photo_keys:
            request_photo_screen(background, f"{kind.name}_report", report_id)
        result = await detail(conn, report_id, user)
        result.possible_matches = await possible_matches(conn, body.category_id, body.occurred_at, user.id)
        return result

    @router.patch("/{report_id}", response_model=ReportDetail, summary="Edit a report (reporter only)")
    async def update_report(report_id: UUID, body: ReportUpdate, background: BackgroundTasks,
                            user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
        before = await editable(conn, report_id, user)
        changes = body.model_dump(exclude_unset=True)
        for required in ("description", "category_id", "occurred_at"):
            if required in changes and changes[required] is None:
                raise HTTPException(422, f"{required} can't be empty.")
        # A new description can match saved keyword searches too (each person is still told once).
        content_changed = (
            changes.get("category_id", before["category_id"]) != before["category_id"]
            or changes.get("occurred_at", before["occurred_at"]) != before["occurred_at"]
            or changes.keys() & {"title", "description"})
        rematch_needed = kind is FOUND and content_changed
        if "occurred_at" in changes:
            changes[kind.when] = changes.pop("occurred_at")
        sql, values = set_clause(changes, start=2)
        async with conn.transaction():
            await conn.execute(f"UPDATE {kind.table} SET {sql} WHERE id = $1", report_id, *values)
            if changes.keys() & {"title", "description"}:
                await screen_text(conn, background, f"{kind.name}_report", report_id)
            if content_changed:
                await needs_rematch(conn, report_id)
            if rematch_needed:
                await rematch(conn, report_id, background)
        if content_changed:
            request_match(background, kind.name, report_id)
        return await detail(conn, report_id, user)

    @router.patch("/{report_id}/status", response_model=ReportDetail,
                  summary="Mark open / closed (reporter only)")
    async def update_status(report_id: UUID, body: StatusUpdate, background: BackgroundTasks,
                            user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
        before = await editable(conn, report_id, user)
        async with conn.transaction():
            await conn.execute(f"UPDATE {kind.table} SET status = $2 WHERE id = $1", report_id, body.status)
            reopened = body.status == "open" and before["status"] != "open"
            if reopened:
                await needs_rematch(conn, report_id)
            if kind is FOUND and reopened:
                await rematch(conn, report_id, background)
        if reopened:
            request_match(background, kind.name, report_id)
        return await detail(conn, report_id, user)

    @router.put("/{report_id}/photos", response_model=ReportDetail,
                summary="Replace the photo list (reporter only)")
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
            await conn.execute(f"UPDATE {kind.table} SET updated_at = now(), match_rev = match_rev + 1 WHERE id = $1",
                               report_id)
        await mark_attached(new_keys)
        background.add_task(delete_objects, sorted(old_keys - set(body.photo_keys)))
        request_match(background, kind.name, report_id)
        if new_keys:
            request_photo_screen(background, f"{kind.name}_report", report_id)
        return await detail(conn, report_id, user)

    @router.get("/{report_id}/matches", response_model=MatchList,
                summary="Possible matches for your own report, best first (reporter or admin)")
    async def list_matches(report_id: UUID, user: CurrentUser = Depends(current_user),
                           conn: asyncpg.Connection = Depends(get_conn)):
        r = await conn.fetchrow(
            f"""SELECT reporter_id, category_id, {kind.when} AS occurred_at, status::text AS status,
                       match_rev, matched_rev FROM {kind.table} WHERE id = $1 AND deleted_at IS NULL""", report_id)
        if r is None:
            raise not_found(f"{kind.name.capitalize()} report")
        if r["reporter_id"] != user.id and not user.is_admin:
            raise forbidden("Only the person who filed this report can see its possible matches.")
        if match_mode() == "off":
            legacy = await possible_matches(conn, r["category_id"], r["occurred_at"], r["reporter_id"])
            return MatchList(status="unavailable",
                             matches=[PossibleMatch(report=m, score=None, strength=None, reasons=[]) for m in legacy])
        rows = await conn.fetch(
            select_for(other, "m.score, m.reasons, ") + f"""
            JOIN lf_matches m ON m.{other.photo_fk} = r.id AND m.{kind.photo_fk} = $1
            WHERE r.status = 'open' AND r.deleted_at IS NULL
            ORDER BY m.score DESC, r.created_at DESC LIMIT 10""", report_id)
        pending = r["status"] == "open" and r["matched_rev"] != r["match_rev"]
        return MatchList(
            status="pending" if pending else "ready",
            matches=[PossibleMatch(report=summary(m, other), score=m["score"], strength=strength(m["score"]),
                                   reasons=list(m["reasons"])) for m in rows])

    @router.delete("/{report_id}", status_code=204,
                   summary="Remove a report (reporter, Lost & Found moderator or admin; FR-10)")
    async def delete_report(report_id: UUID, background: BackgroundTasks,
                            reason: str | None = Query(None, max_length=500),
                            user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
        found = await conn.fetchrow(
            f"""SELECT reporter_id, coalesce(title, description) AS description FROM {kind.table}
                WHERE id = $1 AND deleted_at IS NULL""", report_id)
        reporter = found["reporter_id"] if found else None
        if reporter is None:
            raise not_found(f"{kind.name.capitalize()} report")
        is_owner = reporter == user.id
        if not is_owner and not await is_module_moderator(conn, user, "lost_found"):
            raise forbidden("Only the reporter or a Lost & Found moderator can remove this report.")
        async with conn.transaction():
            await conn.execute(f"UPDATE {kind.table} SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                               report_id, user.id)
            # The row stays for the reports' audit trail; its photos don't need to.
            photo_keys = [r["s3_key"] for r in await conn.fetch(
                f"DELETE FROM {kind.photos} WHERE {kind.photo_fk} = $1 RETURNING s3_key", report_id)]
            await close_reports(conn, f"{kind.name}_report", [report_id], user.id, reason)
            if not is_owner:
                await log_moderation(conn, user.id, f"remove_{kind.name}_report", f"{kind.name}_report",
                                     report_id, reason)
                title = " ".join(found["description"].split())
                title = title if len(title) <= 60 else title[:59].rstrip() + "…"
                payload = {"message": f'A moderator removed your {kind.name} item report "{title}".'
                                      + (f" Reason: {reason}" if reason else ""),
                           "target_type": f"{kind.name}_report", "target_id": str(report_id)}
                await create_notifications(conn, [reporter], "moderation_action", payload)
                background.add_task(deliver_push, [reporter], "moderation_action", payload)
        background.add_task(delete_objects, photo_keys)
        return Response(status_code=204)

    return router


lost_router = build_router(LOST)
found_router = build_router(FOUND)
