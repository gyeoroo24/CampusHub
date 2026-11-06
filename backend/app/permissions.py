"""Permission checks (PRD §3.1, FR-2, FR-3, FR-13), always read from the database.

  admin                         everything, including editing other people's posts
  module moderator              buy_sell / lost_found / placement_hub: remove anyone's posts
  department moderator (AH)     manage courses, materials, feedback and course moderators
                                of every course in their department
  course moderator (AH)         create/read/update/delete materials of their own course,
                                and remove feedback on it (team decision)
  owner / author                edit and delete their own posts
"""
from uuid import UUID

import asyncpg

from .auth import CurrentUser


async def is_module_moderator(conn: asyncpg.Connection, user: CurrentUser, module: str) -> bool:
    if user.is_admin:
        return True
    return await conn.fetchval(
        """SELECT EXISTS (SELECT 1 FROM moderator_assignments
                          WHERE user_id = $1 AND module = $2::module_name
                            AND scope_type = 'module' AND revoked_at IS NULL)""",
        user.id, module)


async def can_manage_department(conn: asyncpg.Connection, user: CurrentUser, department_id: UUID) -> bool:
    if user.is_admin:
        return True
    return await conn.fetchval(
        """SELECT EXISTS (SELECT 1 FROM moderator_assignments
                          WHERE user_id = $1 AND module = 'academic_help' AND scope_type = 'department'
                            AND department_id = $2 AND revoked_at IS NULL)""",
        user.id, department_id)


async def can_manage_course(conn: asyncpg.Connection, user: CurrentUser, course_id: UUID) -> bool:
    """Course moderator of this course, or department moderator of its department."""
    if user.is_admin:
        return True
    return await conn.fetchval(
        """SELECT EXISTS (
               SELECT 1 FROM courses c
               JOIN moderator_assignments m
                 ON m.user_id = $1 AND m.module = 'academic_help' AND m.revoked_at IS NULL
               WHERE c.id = $2 AND (m.course_id = c.id OR m.department_id = c.department_id))""",
        user.id, course_id)


async def can_moderate_forum(conn: asyncpg.Connection, user: CurrentUser, forum_id: UUID) -> bool:
    """Uses the can_moderate_forum() SQL function from schema.sql."""
    return await conn.fetchval("SELECT can_moderate_forum($1, $2)", user.id, forum_id)


async def log_moderation(conn: asyncpg.Connection, moderator_id: UUID, action: str,
                         target_type: str, target_id: UUID, reason: str | None = None) -> None:
    """Audit trail of actions moderators take on other people's content."""
    await conn.execute(
        """INSERT INTO moderation_log (moderator_id, action, target_type, target_id, reason)
           VALUES ($1, $2, $3, $4, $5)""",
        moderator_id, action, target_type, target_id, reason)


async def close_reports(conn: asyncpg.Connection, target_type: str, target_ids: list[UUID],
                        handled_by: UUID, note: str | None = None) -> None:
    """Content was removed: close its open reports so they leave the moderation queue."""
    if target_ids:
        await conn.execute(
            """UPDATE reports SET status = 'actioned', handled_by = $3, handled_at = now(),
                      resolution_note = coalesce($4, 'Removed')
               WHERE target_type = $1 AND target_id = ANY($2::uuid[]) AND status = 'open'""",
            target_type, target_ids, handled_by, note)
