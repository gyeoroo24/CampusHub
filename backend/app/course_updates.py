"""Telling a course's followers what's new there (rev 22): a material shared, feedback posted, a forum
post or reply. One in-app notification (type course_update) per follower, never to whoever did it, plus
push. Forum replies skip people who already get a forum_reply notification for that thread."""
from uuid import UUID

import asyncpg
from fastapi import BackgroundTasks

from .notify import create_notifications, deliver_push


async def notify_course_followers(conn: asyncpg.Connection, background: BackgroundTasks | None, course_id: UUID,
                                  actor_id: UUID | None, what: str, extra: dict | None = None,
                                  skip: list[UUID] | None = None) -> list[UUID]:
    course = await conn.fetchrow("SELECT code, name FROM courses WHERE id = $1", course_id)
    if course is None:
        return []
    skip_ids = set(skip or []) | ({actor_id} if actor_id else set())
    followers = [r["user_id"] for r in await conn.fetch(
        "SELECT user_id FROM course_follows WHERE course_id = $1", course_id) if r["user_id"] not in skip_ids]
    if not followers:
        return []
    payload = {"course_id": str(course_id), "course_code": course["code"],
               "message": f"{course['code']}: {what}"} | (extra or {})
    recipients = await create_notifications(conn, followers, "course_update", payload)
    if background is not None:
        background.add_task(deliver_push, recipients, "course_update", payload)
    return recipients
