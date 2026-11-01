"""Discussion forums (FR-14): forum -> threads -> comments.

Every course and department has one forum, created the first time it's opened.
A thread has a title and an author; its first comment (lowest seq) is the opening post.
The author can edit or remove their thread/comment, and admins can edit anyone's. Admins
and the relevant moderators (see can_moderate_forum() in schema.sql) can remove anyone's.
Removing a thread removes all its comments (database trigger).
"""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user, optional_user
from ..common import Page, PageParams, UserRef, forbidden, make_page, not_found, page_params, text
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..permissions import can_moderate_forum, close_reports, log_moderation

router = APIRouter(tags=["Forums"])


class Forum(BaseModel):
    id: UUID
    scope_type: Literal["course", "department", "company"]
    course_id: UUID | None
    department_id: UUID | None
    company_id: UUID | None
    thread_count: int


class ThreadCreate(BaseModel):
    title: text(200)
    content: text(10_000) = Field(description="The opening post")


class ThreadUpdate(BaseModel):
    title: text(200)


class CommentIn(BaseModel):
    content: text(10_000)


class ThreadSummary(BaseModel):
    id: UUID
    forum_id: UUID
    title: str
    author: UserRef
    comment_count: int
    last_comment_at: datetime | None
    created_at: datetime
    updated_at: datetime


class Comment(BaseModel):
    id: UUID
    seq: int
    author: UserRef
    content: str | None = Field(description="null when the comment was removed")
    removed: bool
    created_at: datetime
    updated_at: datetime


class ThreadDetail(ThreadSummary):
    comments: list[Comment] = Field(description="In order; the first one is the opening post")
    viewer_can_moderate: bool


# ---------------------------------------------------------------- forums
_FORUM_SELECT = """
SELECT f.id, f.scope_type::text AS scope_type, f.course_id, f.department_id, f.company_id,
       (SELECT count(*) FROM threads t WHERE t.forum_id = f.id AND t.deleted_at IS NULL) AS thread_count
FROM forums f
"""


async def _get_or_create_forum(conn: asyncpg.Connection, scope: str, scope_id: UUID) -> Forum:
    table, column = {"course": ("courses", "course_id"), "department": ("departments", "department_id")}[scope]
    row = await conn.fetchrow(_FORUM_SELECT + f" WHERE f.{column} = $1", scope_id)
    if row is None:
        # First visit: create the forum (only once, so later reads don't write).
        if not await conn.fetchval(f"SELECT EXISTS (SELECT 1 FROM {table} WHERE id = $1)", scope_id):
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


# ---------------------------------------------------------------- threads
_THREAD_SELECT = """
SELECT t.id, t.forum_id, t.title, t.created_at, t.updated_at, t.author_id, u.name AS author_name,
       (SELECT count(*) FROM comments c WHERE c.thread_id = t.id AND c.deleted_at IS NULL) AS comment_count,
       (SELECT max(c.created_at) FROM comments c WHERE c.thread_id = t.id AND c.deleted_at IS NULL) AS last_comment_at
FROM threads t JOIN users u ON u.id = t.author_id
"""


def _thread_summary(r: asyncpg.Record) -> ThreadSummary:
    return ThreadSummary(id=r["id"], forum_id=r["forum_id"], title=r["title"],
                         author=UserRef(id=r["author_id"], name=r["author_name"]),
                         comment_count=r["comment_count"], last_comment_at=r["last_comment_at"],
                         created_at=r["created_at"], updated_at=r["updated_at"])


def _comment(r: asyncpg.Record) -> Comment:
    removed = r["deleted_at"] is not None
    return Comment(id=r["id"], seq=r["seq"], author=UserRef(id=r["user_id"], name=r["author_name"]),
                   content=None if removed else r["content"], removed=removed,
                   created_at=r["created_at"], updated_at=r["updated_at"])


async def _thread_detail(conn: asyncpg.Connection, thread_id: UUID, viewer: CurrentUser | None) -> ThreadDetail:
    r = await conn.fetchrow(_THREAD_SELECT + " WHERE t.id = $1 AND t.deleted_at IS NULL", thread_id)
    if r is None:
        raise not_found("Thread")
    comments = await conn.fetch(
        """SELECT c.id, c.seq, c.user_id, u.name AS author_name, c.content, c.created_at, c.updated_at, c.deleted_at
           FROM comments c JOIN users u ON u.id = c.user_id WHERE c.thread_id = $1 ORDER BY c.seq""", thread_id)
    can_mod = bool(viewer) and await can_moderate_forum(conn, viewer, r["forum_id"])
    return ThreadDetail(**_thread_summary(r).model_dump(), comments=[_comment(c) for c in comments],
                        viewer_can_moderate=can_mod)


async def _live_thread(conn: asyncpg.Connection, thread_id: UUID) -> asyncpg.Record:
    row = await conn.fetchrow(
        "SELECT id, forum_id, author_id, title FROM threads WHERE id = $1 AND deleted_at IS NULL", thread_id)
    if row is None:
        raise not_found("Thread")
    return row


@router.get("/forums/{forum_id}/threads", response_model=Page[ThreadSummary], summary="Threads in a forum, newest first")
async def list_threads(forum_id: UUID, page: PageParams = Depends(page_params),
                       conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM forums WHERE id = $1)", forum_id):
        raise not_found("Forum")
    rows = await conn.fetch(
        _THREAD_SELECT + """ WHERE t.forum_id = $1 AND t.deleted_at IS NULL
        ORDER BY t.created_at DESC, t.id DESC LIMIT $2 OFFSET $3""", forum_id, page.limit + 1, page.offset)
    return make_page(rows, page, _thread_summary)


@router.post("/forums/{forum_id}/threads", response_model=ThreadDetail, status_code=201,
             summary="Start a thread with its opening post")
async def create_thread(forum_id: UUID, body: ThreadCreate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM forums WHERE id = $1)", forum_id):
        raise not_found("Forum")
    async with conn.transaction():
        thread_id = await conn.fetchval(
            "INSERT INTO threads (forum_id, author_id, title) VALUES ($1, $2, $3) RETURNING id",
            forum_id, user.id, body.title)
        await conn.execute("INSERT INTO comments (thread_id, user_id, content) VALUES ($1, $2, $3)",
                           thread_id, user.id, body.content)
    return await _thread_detail(conn, thread_id, user)


@router.get("/threads/{thread_id}", response_model=ThreadDetail, summary="A thread with all its comments in order")
async def get_thread(thread_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    return await _thread_detail(conn, thread_id, viewer)


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
@router.post("/threads/{thread_id}/comments", response_model=Comment, status_code=201, summary="Reply in a thread")
async def create_comment(thread_id: UUID, body: CommentIn, background: BackgroundTasks,
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    thread = await _live_thread(conn, thread_id)
    async with conn.transaction():
        comment_id = await conn.fetchval(
            "INSERT INTO comments (thread_id, user_id, content) VALUES ($1, $2, $3) RETURNING id",
            thread_id, user.id, body.content)
        # FR-22 "forum reply": tell the thread's author and everyone who has commented, except the replier.
        participants = await conn.fetch(
            """SELECT DISTINCT user_id FROM comments WHERE thread_id = $1 AND deleted_at IS NULL AND user_id <> $2
               UNION SELECT author_id FROM threads WHERE id = $1 AND author_id <> $2""", thread_id, user.id)
        payload = {"thread_id": str(thread_id), "comment_id": str(comment_id), "forum_id": str(thread["forum_id"]),
                   "message": f"{user.name} replied in “{thread['title']}”"}
        notified = await create_notifications(conn, [p["user_id"] for p in participants], "forum_reply", payload)
    background.add_task(deliver_push, notified, "forum_reply", payload)
    row = await conn.fetchrow(
        """SELECT c.id, c.seq, c.user_id, u.name AS author_name, c.content, c.created_at, c.updated_at, c.deleted_at
           FROM comments c JOIN users u ON u.id = c.user_id WHERE c.id = $1""", comment_id)
    return _comment(row)


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
    updated = await conn.fetchrow(
        """SELECT c.id, c.seq, c.user_id, u.name AS author_name, c.content, c.created_at, c.updated_at, c.deleted_at
           FROM comments c JOIN users u ON u.id = c.user_id WHERE c.id = $1""", comment_id)
    return _comment(updated)


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
