"""User reports: flagging content (a listing selling something prohibited, an abusive comment, ...).

Anyone signed in can report an item once while their report is open. Moderators see the
reports in their own scope, newest first, and resolve them: "actioned" (optionally removing the
content) or "dismissed". Resolving closes every open report on that same item.

The item's owner is told, without naming the reporter: once when it is first reported, and again
when a moderator keeps it up or removes it (with the moderator's note as the reason). Removing a
listing also records a seller-trust strike (app/seller_trust.py), which sends its own notice.

Who sees which reports:
  admin                         all
  Buy & Sell / Lost & Found / Placement Hub moderator    that module's reports
  department moderator          Academic Help reports about their department's courses or forum
  course moderator              Academic Help reports about their course (materials, feedback, forum);
                                they may remove all of these (team decision)
"""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user
from ..common import Page, PageParams, UserRef, forbidden, make_page, not_found, page_params, text
from ..course_updates import notify_course_followers
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import log_moderation
from ..seller_trust import Severity, record_strike

router = APIRouter(tags=["Reports & moderation"])

TargetType = Literal["listing", "lost_report", "found_report", "course_material", "course_feedback",
                     "thread", "comment", "interview_experience", "wanted_post"]
Module = Literal["buy_sell", "lost_found", "academic_help", "placement_hub", "events"]

# target_type -> (table, column in reports)
TARGETS: dict[str, tuple[str, str]] = {
    "listing": ("listings", "listing_id"),
    "lost_report": ("lost_reports", "lost_report_id"),
    "found_report": ("found_reports", "found_report_id"),
    "course_material": ("course_materials", "course_material_id"),
    "course_feedback": ("course_feedback", "course_feedback_id"),
    "thread": ("threads", "thread_id"),
    "comment": ("comments", "comment_id"),
    "interview_experience": ("interview_experiences", "interview_experience_id"),
    "wanted_post": ("wanted_posts", "wanted_post_id"),
}
FIXED_MODULE = {"listing": "buy_sell", "lost_report": "lost_found", "found_report": "lost_found",
                "course_material": "academic_help", "course_feedback": "academic_help",
                "interview_experience": "placement_hub", "wanted_post": "buy_sell"}
FORUM_MODULE = {"course": "academic_help", "department": "academic_help", "company": "placement_hub",
                "event": "events"}

# target_type -> (table, owner column, SQL for a short title, what to call it in a notification)
OWNED: dict[str, tuple[str, str, str, str]] = {
    "listing": ("listings", "seller_id", "title", "listing"),
    "lost_report": ("lost_reports", "reporter_id", "left(coalesce(title, description), 100)", "lost item report"),
    "found_report": ("found_reports", "reporter_id", "left(coalesce(title, description), 100)", "found item report"),
    "course_material": ("course_materials", "uploaded_by", "title", "course material"),
    "course_feedback": ("course_feedback", "author_id", "left(content, 100)", "course review"),
    "thread": ("threads", "author_id", "title", "forum thread"),
    "comment": ("comments", "user_id", "left(content, 100)", "comment"),
    "interview_experience": ("interview_experiences", "author_id", "left(content, 100)", "interview experience"),
    "wanted_post": ("wanted_posts", "author_id", "title", "Wanted post"),
}


def _short(title: str | None, limit: int = 60) -> str:
    title = " ".join((title or "").split())
    return title if len(title) <= limit else title[:limit - 1].rstrip() + "…"


async def _owner_and_title(conn: asyncpg.Connection, target_type: str, target_id: UUID) -> asyncpg.Record | None:
    table, owner, title, _ = OWNED[target_type]
    return await conn.fetchrow(f"SELECT {owner} AS owner_id, {title} AS title FROM {table} WHERE id = $1", target_id)


async def _titles(conn: asyncpg.Connection, rows: list[asyncpg.Record]) -> dict[UUID, str]:
    """Short titles of the reported items, for the moderation queue."""
    by_type: dict[str, list[UUID]] = {}
    for r in rows:
        by_type.setdefault(r["target_type"], []).append(r["target_id"])
    titles: dict[UUID, str] = {}
    for target_type, ids in by_type.items():
        table, _, title, _ = OWNED[target_type]
        for t in await conn.fetch(f"SELECT id, {title} AS title FROM {table} WHERE id = ANY($1::uuid[])", ids):
            titles[t["id"]] = _short(t["title"])
    return titles


async def _tell_owner(conn: asyncpg.Connection, background: BackgroundTasks, target_type: str, target_id: UUID,
                      owner_id: UUID, message: str) -> None:
    payload = {"message": message, "target_type": target_type, "target_id": str(target_id)}
    await create_notifications(conn, [owner_id], "moderation_action", payload)
    background.add_task(deliver_push, [owner_id], "moderation_action", payload)


class ReportCreate(BaseModel):
    target_type: TargetType
    target_id: UUID
    reason: text(1000)


class ResolveRequest(BaseModel):
    action: Literal["actioned", "dismissed"]
    note: text(1000, min_length=0) | None = None
    remove_content: bool = Field(False, description="With action=actioned, also remove the reported item")
    severity: Severity = Field(
        "non_severe", description="Used when target_type=listing and remove_content=true: 'severe' "
                          "(illegal items) immediately blocks the seller; 'non_severe' counts "
                          "toward the strike ladder. Seller trust score, future plan §1.5.")


class Report(BaseModel):
    id: UUID
    module: Module
    target_type: TargetType
    target_id: UUID
    target_title: str | None = Field(None, description="Short title of the reported item (moderation queue)")
    reason: str
    source: Literal["user", "system"] = Field("user", description="system: filed automatically (future plan §1.6)")
    status: Literal["open", "actioned", "dismissed"]
    reporter: UserRef | None = Field(None, description="Shown to moderators only")
    created_at: datetime
    handled_at: datetime | None
    resolution_note: str | None


class ResolveResult(BaseModel):
    reports_resolved: int
    content_removed: bool


async def _target_module(conn: asyncpg.Connection, target_type: str, target_id: UUID) -> str:
    """Which module the item belongs to; 404 if it doesn't exist or was already removed."""
    if target_type == "thread":
        scope = await conn.fetchval(
            """SELECT f.scope_type::text FROM threads t JOIN forums f ON f.id = t.forum_id
               WHERE t.id = $1 AND t.deleted_at IS NULL""", target_id)
    elif target_type == "comment":
        scope = await conn.fetchval(
            """SELECT f.scope_type::text FROM comments c JOIN threads t ON t.id = c.thread_id
               JOIN forums f ON f.id = t.forum_id WHERE c.id = $1 AND c.deleted_at IS NULL""", target_id)
    else:
        table, _ = TARGETS[target_type]
        exists = await conn.fetchval(
            f"SELECT EXISTS (SELECT 1 FROM {table} WHERE id = $1 AND deleted_at IS NULL)", target_id)
        scope = "fixed" if exists else None
    if scope is None:
        raise not_found("Reported item")
    return FIXED_MODULE[target_type] if scope == "fixed" else FORUM_MODULE[scope]


async def _moderator_scope(conn: asyncpg.Connection, user: CurrentUser) -> tuple[list[str], list[UUID], list[UUID]]:
    rows = await conn.fetch(
        """SELECT module::text AS module, scope_type::text AS scope_type, department_id, course_id
           FROM moderator_assignments WHERE user_id = $1 AND revoked_at IS NULL""", user.id)
    modules = [r["module"] for r in rows if r["scope_type"] == "module"]
    departments = [r["department_id"] for r in rows if r["department_id"]]
    courses = [r["course_id"] for r in rows if r["course_id"]]
    return modules, departments, courses


# Each report with the course/department its item belongs to (Academic Help), then filtered
# to what the caller moderates. $1 is_admin, $2 module grants, $3 department grants, $4 course grants.
_SCOPED = """
WITH r AS (
    SELECT rp.*, COALESCE(cm.course_id, cf.course_id, fo.course_id) AS scope_course_id,
           fo.department_id AS forum_department_id
    FROM reports rp
    LEFT JOIN course_materials cm ON cm.id = rp.course_material_id
    LEFT JOIN course_feedback cf ON cf.id = rp.course_feedback_id
    LEFT JOIN comments co ON co.id = rp.comment_id
    LEFT JOIN threads th ON th.id = COALESCE(rp.thread_id, co.thread_id)
    LEFT JOIN forums fo ON fo.id = th.forum_id
)
SELECT r.id, r.module::text AS module, r.target_type::text AS target_type, r.target_id, r.reason,
       r.status::text AS status, r.created_at, r.handled_at, r.resolution_note,
       r.reporter_id, u.name AS reporter_name, r.source::text AS source
FROM r
LEFT JOIN users u ON u.id = r.reporter_id
LEFT JOIN courses sc ON sc.id = r.scope_course_id
WHERE ($1::bool
       OR (r.module <> 'academic_help' AND r.module::text = ANY($2::text[]))
       OR (r.module = 'academic_help'
           AND (r.scope_course_id = ANY($4::uuid[])
                OR sc.department_id = ANY($3::uuid[])
                OR r.forum_department_id = ANY($3::uuid[]))))
"""


def _report(r: asyncpg.Record, with_reporter: bool = True, title: str | None = None) -> Report:
    return Report(id=r["id"], module=r["module"], target_type=r["target_type"], target_id=r["target_id"],
                  target_title=title, reason=r["reason"], status=r["status"], source=r["source"],
                  reporter=(UserRef(id=r["reporter_id"], name=r["reporter_name"])
                            if with_reporter and r["reporter_id"] else None),
                  created_at=r["created_at"], handled_at=r["handled_at"], resolution_note=r["resolution_note"])


@router.post("/reports", response_model=Report, status_code=201, summary="Report content")
async def create_report(body: ReportCreate, background: BackgroundTasks, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    module = await _target_module(conn, body.target_type, body.target_id)
    _, column = TARGETS[body.target_type]
    try:
        async with conn.transaction():
            report_id = await conn.fetchval(
                f"""INSERT INTO reports (reporter_id, module, target_type, {column}, reason)
                    VALUES ($1, $2, $3, $4, $5) RETURNING id""",
                user.id, module, body.target_type, body.target_id, body.reason)
            # Tell the owner once per round of reports (not once per reporter), never who reported it.
            first = await conn.fetchval(
                "SELECT count(*) = 1 FROM reports WHERE target_type = $1 AND target_id = $2 AND status = 'open'",
                body.target_type, body.target_id)
            item = await _owner_and_title(conn, body.target_type, body.target_id)
            if first and item and item["owner_id"] != user.id:
                noun = OWNED[body.target_type][3]
                await _tell_owner(conn, background, body.target_type, body.target_id, item["owner_id"],
                                  f'Your {noun} "{_short(item["title"])}" was reported to a moderator, who will '
                                  "review it. You'll be told what they decide.")
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, "You already have an open report on this item.") from exc
    row = await conn.fetchrow(_SCOPED + " AND r.id = $5", True, [], [], [], report_id)
    return _report(row, with_reporter=False)


@router.get("/me/reports", response_model=Page[Report], summary="Reports I've filed")
async def my_reports(page: PageParams = Depends(page_params), user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(
        _SCOPED + " AND r.reporter_id = $5 ORDER BY r.created_at DESC, r.id DESC LIMIT $6 OFFSET $7",
        True, [], [], [], user.id, page.limit + 1, page.offset)
    return make_page(rows, page, lambda r: _report(r, with_reporter=False))


@router.get("/reports", response_model=Page[Report], summary="Moderation queue (reports in my scope)")
async def list_reports(status: Literal["open", "actioned", "dismissed", "all"] = Query("open", description="all = any status"),
                       module: Module | None = None, page: PageParams = Depends(page_params),
                       user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    modules, departments, courses = await _moderator_scope(conn, user)
    if not (user.is_admin or modules or departments or courses):
        raise forbidden("Only moderators and admins can see reports.")
    rows = await conn.fetch(
        _SCOPED + """ AND ($5::text IS NULL OR r.status::text = $5) AND ($6::text IS NULL OR r.module::text = $6)
        ORDER BY r.created_at DESC, r.id DESC LIMIT $7 OFFSET $8""",
        user.is_admin, modules, departments, courses, None if status == "all" else status, module,
        page.limit + 1, page.offset)
    titles = await _titles(conn, rows)
    return make_page(rows, page, lambda r: _report(r, title=titles.get(r["target_id"])))


@router.post("/reports/{report_id}/resolve", response_model=ResolveResult,
             summary="Resolve a report (closes every open report on the same item)")
async def resolve_report(report_id: UUID, body: ResolveRequest, background: BackgroundTasks,
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    modules, departments, courses = await _moderator_scope(conn, user)
    row = await conn.fetchrow(_SCOPED + " AND r.id = $5", user.is_admin, modules, departments, courses, report_id)
    if row is None:
        if await conn.fetchval("SELECT EXISTS (SELECT 1 FROM reports WHERE id = $1)", report_id):
            raise forbidden("This report is outside the area you moderate.")
        raise not_found("Report")
    if row["status"] != "open":
        raise HTTPException(409, "This report has already been resolved.")
    if body.remove_content and body.action != "actioned":
        raise HTTPException(422, "remove_content only works with action=actioned.")
    target_type, target_id = row["target_type"], row["target_id"]
    removed = False
    async with conn.transaction():
        # Close the reports first: this locks them, so if another moderator resolves the same item
        # at the same moment, one of the two finds nothing left open and gets 409.
        result = await conn.execute(
            """UPDATE reports SET status = $3, handled_by = $4, handled_at = now(), resolution_note = $5
               WHERE target_type = $1 AND target_id = $2 AND status = 'open'""",
            target_type, target_id, body.action, user.id, body.note)
        resolved = int(result.split()[-1])
        if resolved == 0:
            raise HTTPException(409, "This report has already been resolved.")
        if target_type == "listing":
            # A moderator has decided: an automatic hold (§1.6) ends either way. Removal hides it below.
            await conn.execute("UPDATE listings SET held_for_review_at = NULL WHERE id = $1", target_id)
        if target_type == "course_material" and not body.remove_content:
            # A held upload the moderator kept: it appears for everyone, and the course's followers hear of it.
            released = await conn.fetchrow(
                """UPDATE course_materials SET held_for_review_at = NULL
                   WHERE id = $1 AND held_for_review_at IS NOT NULL AND deleted_at IS NULL
                   RETURNING course_id, uploaded_by, title""", target_id)
            if released:
                await notify_course_followers(conn, background, released["course_id"], released["uploaded_by"],
                                              f"new material “{released['title']}”", {"material_id": str(target_id)})
        # Read before removing: a removed Wanted post is deleted outright.
        item = await _owner_and_title(conn, target_type, target_id)
        if body.remove_content:
            if target_type == "listing":
                # Hidden, not deleted: a report-driven removal is reversible via the seller-trust
                # appeal (future plan §1.5) - record_strike() does the actual hiding. A direct
                # DELETE /listings/{id} is a separate path and stays a permanent soft-delete.
                row = await conn.fetchrow(
                    "SELECT seller_id, title FROM listings WHERE id = $1 AND deleted_at IS NULL "
                    "AND hidden_by_strike_id IS NULL FOR UPDATE", target_id)
                removed = row is not None
                if removed:
                    await log_moderation(conn, user.id, "remove_listing", target_type, target_id, body.note)
                    await record_strike(conn, report_id=report_id, listing_id=target_id, seller_id=row["seller_id"],
                                        listing_title=row["title"], severity=body.severity,
                                        moderator_id=user.id, note=body.note)
            elif target_type == "wanted_post":
                # Permanent, like DELETE /wanted/{id}: its reports (this one too) go with it.
                removed = await conn.fetchval("DELETE FROM wanted_posts WHERE id = $1 RETURNING true", target_id) or False
                if removed:
                    await log_moderation(conn, user.id, "remove_wanted_post", target_type, target_id, body.note)
            else:
                table, _ = TARGETS[target_type]
                removed = await conn.fetchval(
                    f"UPDATE {table} SET deleted_at = now(), deleted_by = $2 WHERE id = $1 AND deleted_at IS NULL "
                    "RETURNING true", target_id, user.id) or False
                if removed:
                    await log_moderation(conn, user.id, f"remove_{target_type}", target_type, target_id, body.note)
        await log_moderation(conn, user.id, f"report_{body.action}", target_type, target_id, body.note)
        # A removed listing's owner is told by record_strike(); everyone else hears the outcome here.
        if item and not (removed and target_type == "listing"):
            noun, title = OWNED[target_type][3], _short(item["title"])
            if removed:
                reason = f" Reason: {body.note}" if body.note else ""
                message = f'A moderator removed your {noun} "{title}" after it was reported.{reason}'
            else:
                message = f'A moderator reviewed the report on your {noun} "{title}" and kept it up.'
            await _tell_owner(conn, background, target_type, target_id, item["owner_id"], message)
    return ResolveResult(reports_resolved=resolved, content_removed=removed)
