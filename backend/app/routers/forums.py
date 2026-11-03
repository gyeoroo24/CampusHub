"""Discussion forums (FR-14): forum -> threads -> comments, Reddit style.

Every course, department, company (Placement Hub) and event has one forum, created the first time it's
opened. A thread has a title and an author; its first comment (lowest seq) is the opening post. Replies
can answer the opening post or another reply (parent_id), so the app shows them as a tree.
Signed-in users vote threads and replies up or down (one vote each; every post starts at 0, and voting
the same way again takes the vote back). Threads sort by new or top.
The author can edit or remove their thread/comment, and admins can edit anyone's. Admins
and the relevant moderators (see can_moderate_forum() in schema.sql) can remove anyone's.
Removing a thread removes all its comments (database trigger).
"""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user, optional_user
from ..common import (Page, PageParams, UserRef, forbidden, like_pattern, make_page, not_found, page_params,
                      search_text, text)
from ..course_updates import notify_course_followers
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import can_moderate_forum, close_reports, log_moderation

router = APIRouter(tags=["Forums"])


class Forum(BaseModel):
    id: UUID
    scope_type: Literal["course", "department", "company", "event"]
    course_id: UUID | None
    department_id: UUID | None
    company_id: UUID | None
    event_id: UUID | None = None
    thread_count: int


class ThreadCreate(BaseModel):
    title: text(200)
    content: text(10_000) = Field(description="The opening post")


class ThreadUpdate(BaseModel):
    title: text(200)


class CommentIn(BaseModel):
    content: text(10_000)


class ReplyIn(CommentIn):
    parent_id: UUID | None = Field(None, description="The reply being answered; leave out to answer the opening post")


class VoteIn(BaseModel):
    value: Literal[-1, 0, 1] = Field(description="1 upvote, -1 downvote, 0 take the vote back")


class VoteResult(BaseModel):
    score: int
    viewer_vote: int


class ThreadSummary(BaseModel):
    id: UUID
    forum_id: UUID
    title: str
    author: UserRef
    preview: str | None = Field(None, description="The start of the opening post")
    score: int = Field(0, description="Upvotes minus downvotes")
    viewer_vote: int = Field(0, description="The viewer's vote: 1, -1 or 0 (always 0 for guests)")
    comment_count: int = Field(description="Visible comments, the opening post included")
    reply_count: int = Field(0, description="Visible replies (comment_count without the opening post)")
    last_comment_at: datetime | None
    created_at: datetime
    updated_at: datetime


class Comment(BaseModel):
    id: UUID
    seq: int
    parent_id: UUID | None = Field(None, description="The reply this answers; null = answers the opening post")
    author: UserRef
    content: str | None = Field(description="null when the comment was removed")
    removed: bool
    score: int = 0
    viewer_vote: int = 0
    created_at: datetime
    updated_at: datetime


class ThreadDetail(ThreadSummary):
    comments: list[Comment] = Field(description="In order; the first one is the opening post")
    viewer_can_moderate: bool


# ---------------------------------------------------------------- forums
_FORUM_SELECT = """
SELECT f.id, f.scope_type::text AS scope_type, f.course_id, f.department_id, f.company_id, f.event_id,
       (SELECT count(*) FROM threads t WHERE t.forum_id = f.id AND t.deleted_at IS NULL) AS thread_count
FROM forums f
"""
_SCOPES = {"course": ("courses", "course_id", ""), "department": ("departments", "department_id", ""),
           "company": ("companies", "company_id", ""), "event": ("events", "event_id", " AND deleted_at IS NULL")}


async def _get_or_create_forum(conn: asyncpg.Connection, scope: str, scope_id: UUID) -> Forum:
    table, column, live = _SCOPES[scope]
    row = await conn.fetchrow(_FORUM_SELECT + f" WHERE f.{column} = $1", scope_id)
    if row is None:
        # First visit: create the forum (only once, so later reads don't write).
        if not await conn.fetchval(f"SELECT EXISTS (SELECT 1 FROM {table} WHERE id = $1{live})", scope_id):
            raise not_found(scope.capitalize())
        await conn.execute(
            f"INSERT INTO forums (scope_type, {column}) VALUES ($1, $2) ON CONFLICT ({column}) DO NOTHING",
            scope, scope_id)
        row = await conn.fetchrow(_FORUM_SELECT + f" WHERE f.{column} = $1", scope_id)
    return Forum(**dict(row))


@router.get("/courses/{course_id}/forum", response_model=Forum, summary="A course's forum")
async def course_forum(course_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    return await _get_or_create_forum(conn, "course", course_id)


@router.get("/departments/{department_id}/forum", response_model=Forum, summary="A department's forum")
async def department_forum(department_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    return await _get_or_create_forum(conn, "department", department_id)


@router.get("/companies/{company_id}/forum", response_model=Forum, summary="A company's forum (Placement Hub)")
async def company_forum(company_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    return await _get_or_create_forum(conn, "company", company_id)


@router.get("/events/{event_id}/forum", response_model=Forum, summary="An event's discussion forum")
async def event_forum(event_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    return await _get_or_create_forum(conn, "event", event_id)


# ---------------------------------------------------------------- threads
def _thread_select(viewer: str) -> str:
    """Thread rows; viewer is the placeholder holding the viewer's id (NULL for guests)."""
    return f"""
SELECT t.id, t.forum_id, t.title, t.created_at, t.updated_at, t.author_id, u.name AS author_name,
       (SELECT count(*) FROM comments c WHERE c.thread_id = t.id AND c.deleted_at IS NULL) AS comment_count,
       (SELECT max(c.created_at) FROM comments c WHERE c.thread_id = t.id AND c.deleted_at IS NULL) AS last_comment_at,
       (SELECT left(c.content, 300) FROM comments c WHERE c.thread_id = t.id ORDER BY c.seq LIMIT 1) AS preview,
       (SELECT coalesce(sum(v.value), 0)::int FROM thread_votes v WHERE v.thread_id = t.id) AS score,
       coalesce((SELECT v.value FROM thread_votes v WHERE v.thread_id = t.id AND v.user_id = {viewer}), 0)
           AS viewer_vote
FROM threads t JOIN users u ON u.id = t.author_id
"""


_COMMENT_SELECT = """
SELECT c.id, c.seq, c.parent_id, c.user_id, u.name AS author_name, c.content, c.created_at, c.updated_at,
       c.deleted_at,
       (SELECT coalesce(sum(v.value), 0)::int FROM comment_votes v WHERE v.comment_id = c.id) AS score,
       coalesce((SELECT v.value FROM comment_votes v WHERE v.comment_id = c.id AND v.user_id = $2), 0) AS viewer_vote
FROM comments c JOIN users u ON u.id = c.user_id
"""


def _thread_summary(r: asyncpg.Record) -> ThreadSummary:
    return ThreadSummary(id=r["id"], forum_id=r["forum_id"], title=r["title"],
                         author=UserRef(id=r["author_id"], name=r["author_name"]), preview=r["preview"],
                         score=r["score"], viewer_vote=r["viewer_vote"],
                         comment_count=r["comment_count"], reply_count=max(r["comment_count"] - 1, 0),
                         last_comment_at=r["last_comment_at"], created_at=r["created_at"], updated_at=r["updated_at"])


def _comment(r: asyncpg.Record) -> Comment:
    removed = r["deleted_at"] is not None
    return Comment(id=r["id"], seq=r["seq"], parent_id=r["parent_id"],
                   author=UserRef(id=r["user_id"], name=r["author_name"]),
                   content=None if removed else r["content"], removed=removed,
                   score=r["score"], viewer_vote=r["viewer_vote"],
                   created_at=r["created_at"], updated_at=r["updated_at"])


async def _comment_detail(conn: asyncpg.Connection, comment_id: UUID, viewer: CurrentUser | None) -> Comment:
    return _comment(await conn.fetchrow(_COMMENT_SELECT + " WHERE c.id = $1", comment_id,
                                        viewer.id if viewer else None))


async def _thread_detail(conn: asyncpg.Connection, thread_id: UUID, viewer: CurrentUser | None) -> ThreadDetail:
    viewer_id = viewer.id if viewer else None
    r = await conn.fetchrow(_thread_select("$2") + " WHERE t.id = $1 AND t.deleted_at IS NULL", thread_id, viewer_id)
    if r is None:
        raise not_found("Thread")
    comments = await conn.fetch(_COMMENT_SELECT + " WHERE c.thread_id = $1 ORDER BY c.seq", thread_id, viewer_id)
    can_mod = bool(viewer) and await can_moderate_forum(conn, viewer, r["forum_id"])
    return ThreadDetail(**_thread_summary(r).model_dump(), comments=[_comment(c) for c in comments],
                        viewer_can_moderate=can_mod)


async def _live_thread(conn: asyncpg.Connection, thread_id: UUID) -> asyncpg.Record:
    row = await conn.fetchrow(
        "SELECT id, forum_id, author_id, title FROM threads WHERE id = $1 AND deleted_at IS NULL", thread_id)
    if row is None:
        raise not_found("Thread")
    return row


_THREAD_ORDER = {
    "new": "x.created_at DESC",
    "top": "x.score DESC, x.comment_count DESC, x.created_at DESC",
}


@router.get("/forums/{forum_id}/threads", response_model=Page[ThreadSummary], summary="Threads in a forum")
async def list_threads(forum_id: UUID,
                       sort: Literal["new", "top"] = Query("new", description="new (default) or top"),
                       q: str | None = Query(None, max_length=200, description="Words in the title"),
                       page: PageParams = Depends(page_params), viewer: CurrentUser | None = Depends(optional_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM forums WHERE id = $1)", forum_id):
        raise not_found("Forum")
    q = search_text(q)
    rows = await conn.fetch(
        f"""SELECT * FROM ({_thread_select("$5")} WHERE t.forum_id = $1 AND t.deleted_at IS NULL) x
        WHERE ($4::text IS NULL OR x.title ILIKE '%' || $4 || '%' ESCAPE '\\' OR x.preview ILIKE '%' || $4 || '%' ESCAPE '\\')
        ORDER BY {_THREAD_ORDER[sort]}, x.id DESC LIMIT $2 OFFSET $3""",
        forum_id, page.limit + 1, page.offset, like_pattern(q) if q else None, viewer.id if viewer else None)
    return make_page(rows, page, _thread_summary)


@router.post("/forums/{forum_id}/threads", response_model=ThreadDetail, status_code=201,
             summary="Start a thread with its opening post")
async def create_thread(forum_id: UUID, body: ThreadCreate, background: BackgroundTasks,
                        user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    course_id = await conn.fetchval("SELECT course_id FROM forums WHERE id = $1", forum_id)
    if course_id is None and not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM forums WHERE id = $1)", forum_id):
        raise not_found("Forum")
    async with conn.transaction():
        thread_id = await conn.fetchval(
            "INSERT INTO threads (forum_id, author_id, title) VALUES ($1, $2, $3) RETURNING id",
            forum_id, user.id, body.title)
        await conn.execute("INSERT INTO comments (thread_id, user_id, content) VALUES ($1, $2, $3)",
                           thread_id, user.id, body.content)
        if course_id:   # a course forum: tell the course's followers (rev 22)
            await notify_course_followers(conn, background, course_id, user.id, f"new forum post “{body.title}”",
                                          {"thread_id": str(thread_id), "forum_id": str(forum_id)})
    return await _thread_detail(conn, thread_id, user)


@router.get("/threads/{thread_id}", response_model=ThreadDetail, summary="A thread with all its comments in order")
async def get_thread(thread_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    return await _thread_detail(conn, thread_id, viewer)


async def _vote(conn: asyncpg.Connection, table: str, column: str, item_id: UUID, user: CurrentUser,
                value: int) -> VoteResult:
    async with conn.transaction():
        if value == 0:
            await conn.execute(f"DELETE FROM {table} WHERE {column} = $1 AND user_id = $2", item_id, user.id)
        else:
            await conn.execute(
                f"""INSERT INTO {table} ({column}, user_id, value) VALUES ($1, $2, $3)
                    ON CONFLICT ({column}, user_id) DO UPDATE SET value = EXCLUDED.value, created_at = now()""",
                item_id, user.id, value)
        score = await conn.fetchval(f"SELECT coalesce(sum(value), 0)::int FROM {table} WHERE {column} = $1", item_id)
    return VoteResult(score=score, viewer_vote=value)


@router.put("/threads/{thread_id}/vote", response_model=VoteResult, summary="Vote a thread up or down")
async def vote_thread(thread_id: UUID, body: VoteIn, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _live_thread(conn, thread_id)
    return await _vote(conn, "thread_votes", "thread_id", thread_id, user, body.value)


@router.patch("/threads/{thread_id}", response_model=ThreadDetail, summary="Rename a thread (author or admin)")
async def rename_thread(thread_id: UUID, body: ThreadUpdate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    thread = await _live_thread(conn, thread_id)
    is_author = thread["author_id"] == user.id
    if not is_author and not user.is_admin:
        raise forbidden("Only the thread's author can rename it.")
    async with conn.transaction():
        await conn.execute("UPDATE threads SET title = $2 WHERE id = $1", thread_id, body.title)
        if not is_author:
            await log_moderation(conn, user.id, "rename_thread", "thread", thread_id)
    return await _thread_detail(conn, thread_id, user)


@router.delete("/threads/{thread_id}", status_code=204,
               summary="Remove a thread and all its comments (author, relevant moderator or admin)")
async def delete_thread(thread_id: UUID, reason: str | None = Query(None, max_length=500),
                        user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    thread = await _live_thread(conn, thread_id)
    is_author = thread["author_id"] == user.id
    if not is_author and not await can_moderate_forum(conn, user, thread["forum_id"]):
        raise forbidden("Only the author or a moderator of this forum can remove this thread.")
    async with conn.transaction():
        comment_ids = [r["id"] for r in await conn.fetch(
            "SELECT id FROM comments WHERE thread_id = $1 AND deleted_at IS NULL", thread_id)]
        await conn.execute("UPDATE threads SET deleted_at = now(), deleted_by = $2 WHERE id = $1", thread_id, user.id)
        # The trigger removed its comments too, so close the reports about them as well.
        await close_reports(conn, "thread", [thread_id], user.id, reason)
        await close_reports(conn, "comment", comment_ids, user.id, reason)
        if not is_author:
            await log_moderation(conn, user.id, "remove_thread", "thread", thread_id, reason)
    return Response(status_code=204)


# ---------------------------------------------------------------- comments
@router.post("/threads/{thread_id}/comments", response_model=Comment, status_code=201,
             summary="Reply in a thread, to the opening post or to another reply")
async def create_comment(thread_id: UUID, body: ReplyIn, background: BackgroundTasks,
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    thread = await _live_thread(conn, thread_id)
    if body.parent_id is not None and not await conn.fetchval(
            "SELECT EXISTS (SELECT 1 FROM comments WHERE id = $1 AND thread_id = $2 AND deleted_at IS NULL)",
            body.parent_id, thread_id):
        raise HTTPException(422, "parent_id isn't a visible comment in this thread.")
    async with conn.transaction():
        comment_id = await conn.fetchval(
            "INSERT INTO comments (thread_id, user_id, content, parent_id) VALUES ($1, $2, $3, $4) RETURNING id",
            thread_id, user.id, body.content, body.parent_id)
        # FR-22 "forum reply": tell the thread's author and everyone who has commented, except the replier.
        participants = await conn.fetch(
            """SELECT DISTINCT user_id FROM comments WHERE thread_id = $1 AND deleted_at IS NULL AND user_id <> $2
               UNION SELECT author_id FROM threads WHERE id = $1 AND author_id <> $2""", thread_id, user.id)
        payload = {"thread_id": str(thread_id), "comment_id": str(comment_id), "forum_id": str(thread["forum_id"]),
                   "message": f"{user.name} replied in “{thread['title']}”"}
        notified = await create_notifications(conn, [p["user_id"] for p in participants], "forum_reply", payload)
        course_id = await conn.fetchval("SELECT course_id FROM forums WHERE id = $1", thread["forum_id"])
        if course_id:   # a course forum: its followers hear too, unless they're already told above
            await notify_course_followers(conn, background, course_id, user.id, f"new reply in “{thread['title']}”",
                                          {"thread_id": str(thread_id), "forum_id": str(thread["forum_id"])},
                                          skip=notified)
    background.add_task(deliver_push, notified, "forum_reply", payload)
    return await _comment_detail(conn, comment_id, user)


async def _live_comment(conn: asyncpg.Connection, comment_id: UUID) -> asyncpg.Record:
    row = await conn.fetchrow(
        """SELECT c.user_id, t.forum_id FROM comments c JOIN threads t ON t.id = c.thread_id
           WHERE c.id = $1 AND c.deleted_at IS NULL AND t.deleted_at IS NULL""", comment_id)
    if row is None:
        raise not_found("Comment")
    return row


@router.patch("/comments/{comment_id}", response_model=Comment, summary="Edit a comment (author or admin)")
async def update_comment(comment_id: UUID, body: CommentIn, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    row = await _live_comment(conn, comment_id)
    is_author = row["user_id"] == user.id
    if not is_author and not user.is_admin:
        raise forbidden("Only the author can edit this comment.")
    async with conn.transaction():
        await conn.execute("UPDATE comments SET content = $2 WHERE id = $1", comment_id, body.content)
        if not is_author:
            await log_moderation(conn, user.id, "edit_comment", "comment", comment_id)
    return await _comment_detail(conn, comment_id, user)


@router.put("/comments/{comment_id}/vote", response_model=VoteResult, summary="Vote a reply up or down")
async def vote_comment(comment_id: UUID, body: VoteIn, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    await _live_comment(conn, comment_id)
    return await _vote(conn, "comment_votes", "comment_id", comment_id, user, body.value)


@router.delete("/comments/{comment_id}", status_code=204, summary="Remove a comment (author, relevant moderator or admin)")
async def delete_comment(comment_id: UUID, reason: str | None = Query(None, max_length=500),
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await _live_comment(conn, comment_id)
    is_author = row["user_id"] == user.id
    if not is_author and not await can_moderate_forum(conn, user, row["forum_id"]):
        raise forbidden("Only the author or a moderator of this forum can remove this comment.")
    async with conn.transaction():
        await conn.execute("UPDATE comments SET deleted_at = now(), deleted_by = $2 WHERE id = $1", comment_id, user.id)
        await close_reports(conn, "comment", [comment_id], user.id, reason)
        if not is_author:
            await log_moderation(conn, user.id, "remove_comment", "comment", comment_id, reason)
    return Response(status_code=204)
