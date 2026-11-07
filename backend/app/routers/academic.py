"""Academic Help: departments, courses, materials and feedback (FR-11, FR-12, FR-13, scenario 4).

  departments        admins create/rename/delete
  courses            admins and department moderators add/edit/remove courses in their department
  materials          a shared repository (rev 22): anyone signed in shares files (up to 100 MB, tagged
                     pyq / quiz / notes ...); every file is checked (app/material_check.py) and
                     suspicious ones are held for the course's moderators. The uploader edits/removes
                     their own; course and department moderators edit/remove any; anyone can read
  follows            anyone signed in follows a course: new materials, feedback and forum posts notify
                     them (app/course_updates.py)
  feedback           any signed-in user posts one review per course (optionally anonymous); the author,
                     department moderators and admins edit;
                     the author, moderators of the course (course or department level) and admins remove

Deleting a course deletes everything under it (materials, feedback, its forum, threads,
comments, course moderator roles and reports about them) — a team decision.
"""
import asyncio
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field

from .. import cache
from ..auth import CurrentUser, current_user, optional_user
from ..common import Page, PageParams, UserRef, forbidden, make_page, not_found, page_params, set_clause, text
from ..course_updates import notify_course_followers
from ..db import get_conn
from ..material_check import SPAM_PER_HOUR, Rejected, check_material, text_flags
from ..notify import create_notifications
from ..permissions import can_manage_course, can_manage_department, close_reports, log_moderation
from ..storage import delete_objects, file_url, get_object, mark_attached, verify_own_uploads

router = APIRouter(tags=["Academic Help"])

MaterialType = Literal["notes", "slides", "past_assignment", "exam_material", "other"]
MaterialTag = Literal["pyq", "quiz", "assignment", "notes", "slides", "lab", "solutions", "cheat_sheet",
                      "textbook", "project", "other"]
# The older single type, kept filled in from the tags for clients that still read it.
_TYPE_FOR_TAG = {"pyq": "exam_material", "quiz": "exam_material", "solutions": "exam_material",
                 "assignment": "past_assignment", "lab": "past_assignment", "project": "past_assignment",
                 "notes": "notes", "cheat_sheet": "notes", "textbook": "notes", "slides": "slides"}


def _type_from_tags(tags: list[str], fallback: str = "other") -> str:
    return next((_TYPE_FOR_TAG[t] for t in tags if t in _TYPE_FOR_TAG), fallback)


# ---------------------------------------------------------------- models
class DepartmentIn(BaseModel):
    name: text(120, single_line=True)


class Department(BaseModel):
    id: UUID
    name: str
    course_count: int
    created_at: datetime
    updated_at: datetime


class CourseCreate(BaseModel):
    code: text(20) = Field(examples=["DS 252"])
    name: text(200, single_line=True)


class CourseUpdate(BaseModel):
    code: text(20) | None = None
    name: text(200, single_line=True) | None = None


class Course(BaseModel):
    id: UUID
    department_id: UUID
    code: str
    name: str
    material_count: int
    feedback_count: int
    has_content: bool = Field(description="False means show 'No data yet' (FR-11)")
    following: bool = Field(False, description="The viewer follows this course (always false for guests)")
    follower_count: int = 0
    created_at: datetime
    updated_at: datetime


class MaterialCreate(BaseModel):
    title: text(200, single_line=True)
    tags: list[MaterialTag] = Field(default_factory=list, max_length=5, description="What it is: pyq, quiz, notes ...")
    description: text(2000, min_length=0) | None = None
    material_type: MaterialType | None = Field(None, description="Older single type; filled in from tags if left out")
    file_name: str | None = Field(None, max_length=255, description="The file's original name, shown on downloads")
    s3_key: str = Field(description="From POST /uploads with kind=course_material and this course_id")


class MaterialUpdate(BaseModel):
    title: text(200, single_line=True) | None = None
    tags: list[MaterialTag] | None = Field(None, max_length=5)
    description: text(2000, min_length=0) | None = None
    material_type: MaterialType | None = None


class Material(BaseModel):
    id: UUID
    course_id: UUID
    title: str
    material_type: MaterialType
    tags: list[str] = Field(default_factory=list)
    description: str | None = None
    file_name: str | None = None
    size_bytes: int | None = None
    content_type: str | None = None
    held: bool = Field(False, description="Hidden for a moderator's review; only the uploader and moderators see it")
    can_edit: bool = Field(False, description="The viewer uploaded it or moderates the course")
    download_url: str
    uploaded_by: UserRef
    created_at: datetime
    updated_at: datetime


class FeedbackIn(BaseModel):
    content: text(5000)
    is_anonymous: bool = Field(False, description="Hide your name from everyone else")


class FeedbackUpdate(BaseModel):
    content: text(5000) | None = None
    is_anonymous: bool | None = None


class Feedback(BaseModel):
    id: UUID
    course_id: UUID
    author: UserRef | None = Field(description="null for anonymous feedback (except to its author) and for guests")
    is_anonymous: bool
    is_mine: bool = Field(description="True when the viewer wrote it, so the app can offer edit and delete")
    can_remove: bool = Field(description="True when the viewer may remove it: its author, or a moderator of the "
                                         "course (course or department moderator, or admin)")
    content: str
    created_at: datetime
    updated_at: datetime


# ---------------------------------------------------------------- departments
_DEPT_SELECT = """
SELECT d.id, d.name, d.created_at, d.updated_at,
       (SELECT count(*) FROM courses c WHERE c.department_id = d.id) AS course_count
FROM departments d
"""


@router.get("/departments", response_model=list[Department], summary="All departments")
async def list_departments(conn: asyncpg.Connection = Depends(get_conn)):
    async def _fetch():
        return [Department(**dict(r)) for r in await conn.fetch(_DEPT_SELECT + " ORDER BY d.name")]

    # Not viewer-scoped: static reference data, same for every caller.
    return await cache.get_or_set(cache.build_key("academics:departments", None), None, _fetch)


@router.post("/departments", response_model=Department, status_code=201, summary="Add a department (admin)")
async def create_department(body: DepartmentIn, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
    if not user.is_admin:
        raise forbidden("Only admins can add departments.")
    dept_id = await conn.fetchval("INSERT INTO departments (name) VALUES ($1) RETURNING id", body.name.strip())
    return Department(**dict(await conn.fetchrow(_DEPT_SELECT + " WHERE d.id = $1", dept_id)))


@router.patch("/departments/{department_id}", response_model=Department, summary="Rename a department (admin)")
async def rename_department(department_id: UUID, body: DepartmentIn, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
    if not user.is_admin:
        raise forbidden("Only admins can rename departments.")
    if await conn.fetchval("UPDATE departments SET name = $2 WHERE id = $1 RETURNING id",
                           department_id, body.name.strip()) is None:
        raise not_found("Department")
    return Department(**dict(await conn.fetchrow(_DEPT_SELECT + " WHERE d.id = $1", department_id)))


@router.delete("/departments/{department_id}", status_code=204,
               summary="Delete a department and everything in it (admin)")
async def delete_department(department_id: UUID, background: BackgroundTasks,
                            user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    if not user.is_admin:
        raise forbidden("Only admins can delete departments.")
    async with conn.transaction():
        keys = [r["file_s3_key"] for r in await conn.fetch(
            "SELECT m.file_s3_key FROM course_materials m JOIN courses c ON c.id = m.course_id "
            "WHERE c.department_id = $1", department_id)]
        if await conn.fetchval("DELETE FROM departments WHERE id = $1 RETURNING id", department_id) is None:
            raise not_found("Department")
        await log_moderation(conn, user.id, "delete_department", "department", department_id)
    background.add_task(delete_objects, keys)
    return Response(status_code=204)


# ---------------------------------------------------------------- courses
_COURSE_SELECT = """
SELECT c.id, c.department_id, c.code, c.name, c.created_at, c.updated_at,
       (SELECT count(*) FROM course_materials m WHERE m.course_id = c.id AND m.deleted_at IS NULL
          AND m.held_for_review_at IS NULL) AS material_count,
       (SELECT count(*) FROM course_feedback f WHERE f.course_id = c.id AND f.deleted_at IS NULL) AS feedback_count,
       (SELECT count(*) FROM course_follows w WHERE w.course_id = c.id)::int AS follower_count
FROM courses c
"""


def _course(r: asyncpg.Record, following: bool = False) -> Course:
    return Course(**dict(r), following=following, has_content=(r["material_count"] + r["feedback_count"]) > 0)


async def _course_department(conn: asyncpg.Connection, course_id: UUID) -> UUID:
    department_id = await conn.fetchval("SELECT department_id FROM courses WHERE id = $1", course_id)
    if department_id is None:
        raise not_found("Course")
    return department_id


@router.get("/departments/{department_id}/courses", response_model=list[Course],
            summary="Courses in a department, with whether each has content (FR-11)")
async def list_courses(department_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    async def _fetch():
        if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM departments WHERE id = $1)", department_id):
            raise not_found("Department")
        rows = await conn.fetch(_COURSE_SELECT + " WHERE c.department_id = $1 ORDER BY c.code", department_id)
        followed = set()
        if viewer is not None and rows:
            followed = {r["course_id"] for r in await conn.fetch(
                "SELECT course_id FROM course_follows WHERE user_id = $1 AND course_id = ANY($2::uuid[])",
                viewer.id, [r["id"] for r in rows])}
        return [_course(r, following=r["id"] in followed) for r in rows]

    # Viewer-scoped: "following" depends on who's asking.
    key = cache.build_key("academics:courses", viewer.id if viewer else None, department_id)
    return await cache.get_or_set(key, None, _fetch)


@router.get("/courses/{course_id}", response_model=Course, summary="One course")
async def get_course(course_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    r = await conn.fetchrow(_COURSE_SELECT + " WHERE c.id = $1", course_id)
    if r is None:
        raise not_found("Course")
    following = viewer is not None and await conn.fetchval(
        "SELECT EXISTS (SELECT 1 FROM course_follows WHERE course_id = $1 AND user_id = $2)", course_id, viewer.id)
    return _course(r, following)


@router.put("/courses/{course_id}/follow", response_model=Course,
            summary="Follow a course: new materials, feedback and forum posts there notify you")
async def follow_course(course_id: UUID, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    await conn.execute("INSERT INTO course_follows (user_id, course_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                       user.id, course_id)
    return await get_course(course_id, user, conn)


@router.delete("/courses/{course_id}/follow", response_model=Course, summary="Stop following a course")
async def unfollow_course(course_id: UUID, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    await conn.execute("DELETE FROM course_follows WHERE user_id = $1 AND course_id = $2", user.id, course_id)
    return await get_course(course_id, user, conn)


@router.post("/departments/{department_id}/courses", response_model=Course, status_code=201,
             summary="Add a course (admin or department moderator)")
async def create_course(department_id: UUID, body: CourseCreate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM departments WHERE id = $1)", department_id):
        raise not_found("Department")
    if not await can_manage_department(conn, user, department_id):
        raise forbidden("Only admins and this department's moderators can add courses.")
    try:
        course_id = await conn.fetchval(
            "INSERT INTO courses (department_id, code, name) VALUES ($1, $2, $3) RETURNING id",
            department_id, body.code.strip(), body.name.strip())
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, "This department already has a course with that code.") from exc
    return _course(await conn.fetchrow(_COURSE_SELECT + " WHERE c.id = $1", course_id))


@router.patch("/courses/{course_id}", response_model=Course, summary="Edit a course (admin or department moderator)")
async def update_course(course_id: UUID, body: CourseUpdate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    if not await can_manage_department(conn, user, await _course_department(conn, course_id)):
        raise forbidden("Only admins and this department's moderators can edit courses.")
    changes = {k: v.strip() for k, v in body.model_dump(exclude_unset=True).items() if v is not None}
    sql, values = set_clause(changes, start=2)
    await conn.execute(f"UPDATE courses SET {sql} WHERE id = $1", course_id, *values)
    return _course(await conn.fetchrow(_COURSE_SELECT + " WHERE c.id = $1", course_id))


@router.delete("/courses/{course_id}", status_code=204,
               summary="Delete a course and everything under it (admin or department moderator)")
async def delete_course(course_id: UUID, background: BackgroundTasks, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    if not await can_manage_department(conn, user, await _course_department(conn, course_id)):
        raise forbidden("Only admins and this department's moderators can delete courses.")
    async with conn.transaction():
        keys = [r["file_s3_key"] for r in await conn.fetch(
            "SELECT file_s3_key FROM course_materials WHERE course_id = $1", course_id)]
        await conn.execute("DELETE FROM courses WHERE id = $1", course_id)
        await log_moderation(conn, user.id, "delete_course", "course", course_id)
    background.add_task(delete_objects, keys)
    return Response(status_code=204)


# ---------------------------------------------------------------- materials (a shared repository, rev 22)
_MATERIAL_SELECT = """
SELECT m.id, m.course_id, m.title, m.material_type::text AS material_type, m.file_s3_key, m.tags, m.description,
       m.file_name, m.size_bytes, m.content_type, m.held_for_review_at IS NOT NULL AS held,
       m.created_at, m.updated_at, u.id AS uploader_id, u.name AS uploader_name
FROM course_materials m JOIN users u ON u.id = m.uploaded_by
"""


def _material(r: asyncpg.Record, can_edit: bool = False) -> Material:
    return Material(id=r["id"], course_id=r["course_id"], title=r["title"], material_type=r["material_type"],
                    tags=list(r["tags"] or []), description=r["description"], file_name=r["file_name"],
                    size_bytes=r["size_bytes"], content_type=r["content_type"], held=r["held"], can_edit=can_edit,
                    download_url=file_url(r["file_s3_key"]),
                    uploaded_by=UserRef(id=r["uploader_id"], name=r["uploader_name"]),
                    created_at=r["created_at"], updated_at=r["updated_at"])


async def _material_course(conn: asyncpg.Connection, material_id: UUID) -> asyncpg.Record:
    row = await conn.fetchrow(
        "SELECT course_id, uploaded_by, title FROM course_materials WHERE id = $1 AND deleted_at IS NULL", material_id)
    if row is None:
        raise not_found("Material")
    return row


@router.get("/materials/{material_id}", response_model=Material,
            summary="One course material, by id (e.g. for the reports queue)")
async def get_material(material_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(_MATERIAL_SELECT + " WHERE m.id = $1", material_id)
    if row is None:
        raise not_found("Material")
    moderator = viewer is not None and await can_manage_course(conn, viewer, row["course_id"])
    can_edit = moderator or (viewer is not None and viewer.id == row["uploader_id"])
    return _material(row, can_edit)


@router.get("/courses/{course_id}/materials", response_model=Page[Material], summary="A course's materials")
async def list_materials(course_id: UUID, material_type: MaterialType | None = None,
                         tag: MaterialTag | None = Query(None, description="Only materials with this tag"),
                         q: str | None = Query(None, max_length=200, description="Words in the title or description"),
                         page: PageParams = Depends(page_params), viewer: CurrentUser | None = Depends(optional_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    """Held materials (waiting for a moderator) show only to their uploader and the course's moderators."""
    await _course_department(conn, course_id)
    moderator = viewer is not None and await can_manage_course(conn, viewer, course_id)
    viewer_id = viewer.id if viewer else None
    rows = await conn.fetch(
        _MATERIAL_SELECT + """
        WHERE m.course_id = $1 AND m.deleted_at IS NULL AND ($2::text IS NULL OR m.material_type::text = $2)
          AND ($5::text IS NULL OR $5 = ANY(m.tags))
          AND ($6::text IS NULL OR m.title ILIKE '%' || $6 || '%' OR m.description ILIKE '%' || $6 || '%')
          AND (m.held_for_review_at IS NULL OR $7 OR m.uploaded_by = $8)
        ORDER BY m.created_at DESC, m.id DESC LIMIT $3 OFFSET $4""",
        course_id, material_type, page.limit + 1, page.offset, tag, (q or "").strip() or None, moderator, viewer_id)
    return make_page(rows, page, lambda r: _material(r, moderator or r["uploader_id"] == viewer_id))


@router.post("/courses/{course_id}/materials", response_model=Material, status_code=201,
             summary="Share a material with the course (anyone signed in; checked, and held if it looks wrong)")
async def create_material(course_id: UUID, body: MaterialCreate, background: BackgroundTasks,
                          user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    await verify_own_uploads([body.s3_key], "course_material", user.id, course_id)
    # Open the file and check what it really is (app/material_check.py) before anyone else can get it.
    data, content_type = await get_object(body.s3_key)
    try:
        result = await asyncio.to_thread(check_material, data, content_type, body.file_name or "")
    except Rejected as exc:
        background.add_task(delete_objects, [body.s3_key])
        raise HTTPException(422, str(exc)) from exc
    flags = result.flags + text_flags(body.title, body.description)
    recent = await conn.fetchval(
        "SELECT count(*) FROM course_materials WHERE uploaded_by = $1 AND created_at > now() - interval '1 hour'",
        user.id)
    if recent >= SPAM_PER_HOUR:
        flags.append(f"more than {SPAM_PER_HOUR} uploads in an hour")
    tags = list(dict.fromkeys(body.tags))
    async with conn.transaction():
        # One uploaded file backs one material (the lock stops two requests attaching it at once).
        await conn.execute("SELECT pg_advisory_xact_lock(hashtext($1))", body.s3_key)
        if await conn.fetchval("SELECT EXISTS (SELECT 1 FROM course_materials WHERE file_s3_key = $1)",
                               body.s3_key):
            raise HTTPException(409, "This file is already attached to a material. Upload it again for a new one.")
        material_id = await conn.fetchval(
            """INSERT INTO course_materials (course_id, uploaded_by, title, material_type, file_s3_key, tags,
                                             description, file_name, size_bytes, content_type, held_for_review_at)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, CASE WHEN $11 THEN now() END) RETURNING id""",
            course_id, user.id, body.title, body.material_type or _type_from_tags(tags), body.s3_key, tags,
            (body.description or "").strip() or None, (body.file_name or "")[:255] or None, len(data), content_type,
            bool(flags))
        if flags:
            # Hidden until a course moderator decides (the report shows in their queue).
            await conn.execute(
                """INSERT INTO reports (source, module, target_type, course_material_id, reason)
                   VALUES ('system', 'academic_help', 'course_material', $1, left($2, 1000))""",
                material_id, "Automatic flag: " + "; ".join(flags))
            await create_notifications(conn, [user.id], "moderation_action", {
                "message": f'Your upload "{body.title}" is waiting for a moderator to check it ({"; ".join(flags)}). '
                           "It appears for others once they approve it.",
                "target_type": "course_material", "target_id": str(material_id)})
        else:
            await notify_course_followers(conn, background, course_id, user.id, f"new material “{body.title}”",
                                          {"material_id": str(material_id)})
    await mark_attached([body.s3_key])
    return _material(await conn.fetchrow(_MATERIAL_SELECT + " WHERE m.id = $1", material_id), True)


async def _may_change_material(conn: asyncpg.Connection, user: CurrentUser, row: asyncpg.Record) -> bool:
    """The uploader, or a moderator of the course (True when it's a moderator changing someone else's)."""
    if row["uploaded_by"] == user.id:
        return False
    if await can_manage_course(conn, user, row["course_id"]):
        return True
    raise forbidden("Only whoever shared this material or the course's moderators can change it.")


@router.patch("/materials/{material_id}", response_model=Material, summary="Edit a material's title, tags or description")
async def update_material(material_id: UUID, body: MaterialUpdate, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    row = await _material_course(conn, material_id)
    as_moderator = await _may_change_material(conn, user, row)
    changes = body.model_dump(exclude_unset=True)
    if "title" in changes and changes["title"] is None:
        raise HTTPException(422, "title can't be empty.")
    if changes.get("tags") is not None:
        changes["tags"] = list(dict.fromkeys(changes["tags"]))
        changes.setdefault("material_type", _type_from_tags(changes["tags"]))
    elif "tags" in changes:
        changes["tags"] = []
    if "description" in changes:
        changes["description"] = (changes["description"] or "").strip() or None
    if changes.get("material_type") is None:
        changes.pop("material_type", None)
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        await conn.execute(f"UPDATE course_materials SET {sql}, updated_at = now() WHERE id = $1", material_id, *values)
        if as_moderator:
            await log_moderation(conn, user.id, "edit_course_material", "course_material", material_id)
    return _material(await conn.fetchrow(_MATERIAL_SELECT + " WHERE m.id = $1", material_id), True)


@router.delete("/materials/{material_id}", status_code=204, summary="Remove a material (its uploader or a moderator)")
async def delete_material(material_id: UUID, reason: str | None = Query(None, max_length=500),
                          user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await _material_course(conn, material_id)
    as_moderator = await _may_change_material(conn, user, row)
    async with conn.transaction():
        await conn.execute("UPDATE course_materials SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                           material_id, user.id)
        await close_reports(conn, "course_material", [material_id], user.id, reason)
        if as_moderator:
            await log_moderation(conn, user.id, "remove_course_material", "course_material", material_id, reason)
    return Response(status_code=204)


# ---------------------------------------------------------------- feedback
_FEEDBACK_SELECT = """
SELECT f.id, f.course_id, f.content, f.is_anonymous, f.created_at, f.updated_at,
       u.id AS author_id, u.name AS author_name
FROM course_feedback f JOIN users u ON u.id = f.author_id
"""


def _feedback(r: asyncpg.Record, viewer: CurrentUser | None, moderator: bool = False) -> Feedback:
    """Names are shown only to signed-in viewers, and never for anonymous feedback (except to its author).
    [moderator] is whether the viewer moderates this course (see can_manage_course)."""
    mine = viewer is not None and viewer.id == r["author_id"]
    show_name = mine or (viewer is not None and not r["is_anonymous"])
    return Feedback(id=r["id"], course_id=r["course_id"], content=r["content"], is_anonymous=r["is_anonymous"],
                    is_mine=mine, can_remove=mine or moderator, author=UserRef(id=r["author_id"], name=r["author_name"]) if show_name else None,
                    created_at=r["created_at"], updated_at=r["updated_at"])


async def _may_change_feedback(conn: asyncpg.Connection, user: CurrentUser, feedback_id: UUID,
                               removing: bool) -> asyncpg.Record:
    """Editing: the author, a moderator of the course's department (scenario 4), or an admin.
    Removing: also a course moderator of that course (team decision)."""
    row = await conn.fetchrow(
        """SELECT f.author_id, f.course_id, c.department_id FROM course_feedback f JOIN courses c ON c.id = f.course_id
           WHERE f.id = $1 AND f.deleted_at IS NULL""", feedback_id)
    if row is None:
        raise not_found("Feedback")
    if row["author_id"] == user.id:
        return row
    if removing:
        if not await can_manage_course(conn, user, row["course_id"]):
            raise forbidden("Only the author or this course's moderators can remove this feedback.")
    elif not await can_manage_department(conn, user, row["department_id"]):
        raise forbidden("Only the author or this department's moderators can edit this feedback.")
    return row


@router.get("/feedback/{feedback_id}", response_model=Feedback,
            summary="One piece of feedback, by id (e.g. for the reports queue)")
async def get_feedback(feedback_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(_FEEDBACK_SELECT + " WHERE f.id = $1", feedback_id)
    if row is None:
        raise not_found("Feedback")
    moderator = viewer is not None and await can_manage_course(conn, viewer, row["course_id"])
    return _feedback(row, viewer, moderator)


@router.get("/courses/{course_id}/feedback", response_model=Page[Feedback], summary="A course's feedback")
async def list_feedback(course_id: UUID, page: PageParams = Depends(page_params),
                        viewer: CurrentUser | None = Depends(optional_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    rows = await conn.fetch(
        _FEEDBACK_SELECT + """ WHERE f.course_id = $1 AND f.deleted_at IS NULL
        ORDER BY f.created_at DESC, f.id DESC LIMIT $2 OFFSET $3""", course_id, page.limit + 1, page.offset)
    moderator = viewer is not None and await can_manage_course(conn, viewer, course_id)
    return make_page(rows, page, lambda r: _feedback(r, viewer, moderator))


@router.get("/courses/{course_id}/feedback/mine", response_model=Feedback, summary="My feedback on a course, if any")
async def my_feedback(course_id: UUID, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    row = await conn.fetchrow(_FEEDBACK_SELECT + """ WHERE f.course_id = $1 AND f.author_id = $2
                              AND f.deleted_at IS NULL""", course_id, user.id)
    if row is None:
        raise not_found("Your feedback on this course")
    return _feedback(row, user)


@router.post("/courses/{course_id}/feedback", response_model=Feedback, status_code=201,
             summary="Post feedback on a course (FR-12); one per person per course")
async def create_feedback(course_id: UUID, body: FeedbackIn, background: BackgroundTasks,
                          user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    try:
        async with conn.transaction():
            feedback_id = await conn.fetchval(
                "INSERT INTO course_feedback (course_id, author_id, content, is_anonymous) VALUES ($1, $2, $3, $4) "
                "RETURNING id", course_id, user.id, body.content, body.is_anonymous)
            await notify_course_followers(conn, background, course_id, user.id, "new feedback posted",
                                          {"feedback_id": str(feedback_id)})
    except asyncpg.UniqueViolationError as exc:
        # One review per person keeps the survival guide's numbers from being skewed by repeat posts.
        raise HTTPException(409, "You've already reviewed this course. Edit your feedback instead.") from exc
    return _feedback(await conn.fetchrow(_FEEDBACK_SELECT + " WHERE f.id = $1", feedback_id), user)


@router.patch("/feedback/{feedback_id}", response_model=Feedback,
              summary="Edit feedback (author, department moderator, admin)")
async def update_feedback(feedback_id: UUID, body: FeedbackUpdate, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    row = await _may_change_feedback(conn, user, feedback_id, removing=False)
    changes = body.model_dump(exclude_unset=True)
    if any(changes.get(k, 0) is None for k in ("content", "is_anonymous")):
        raise HTTPException(422, "content and is_anonymous can't be empty.")
    if "is_anonymous" in changes and row["author_id"] != user.id:
        raise forbidden("Only the author can change whether their name is shown.")
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        await conn.execute(f"UPDATE course_feedback SET {sql} WHERE id = $1", feedback_id, *values)
        if row["author_id"] != user.id:
            await log_moderation(conn, user.id, "edit_course_feedback", "course_feedback", feedback_id)
    return _feedback(await conn.fetchrow(_FEEDBACK_SELECT + " WHERE f.id = $1", feedback_id), user)


@router.delete("/feedback/{feedback_id}", status_code=204,
               summary="Remove feedback (author, course or department moderator, admin)")
async def delete_feedback(feedback_id: UUID, reason: str | None = Query(None, max_length=500),
                          user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await _may_change_feedback(conn, user, feedback_id, removing=True)
    async with conn.transaction():
        await conn.execute("UPDATE course_feedback SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                           feedback_id, user.id)
        await close_reports(conn, "course_feedback", [feedback_id], user.id, reason)
        if row["author_id"] != user.id:
            await log_moderation(conn, user.id, "remove_course_feedback", "course_feedback", feedback_id, reason)
    return Response(status_code=204)
