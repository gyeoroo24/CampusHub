"""Academic Help: departments, courses, materials and feedback (FR-11, FR-12, FR-13, scenario 4).

  departments        admins create/rename/delete
  courses            admins and department moderators add/edit/remove courses in their department
  materials          course moderators (own course) and department moderators (their department)
                     create/edit/remove; anyone can read
  feedback           any signed-in user posts; the author, department moderators and admins edit/remove

Deleting a course deletes everything under it (materials, feedback, its forum, threads,
comments, course moderator roles and reports about them) — a team decision.
"""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user
from ..common import Page, PageParams, UserRef, forbidden, make_page, not_found, page_params, set_clause
from ..db import get_conn
from ..permissions import can_manage_course, can_manage_department, log_moderation
from ..storage import delete_objects, file_url, verify_own_uploads

router = APIRouter(tags=["Academic Help"])

MaterialType = Literal["notes", "slides", "past_assignment", "exam_material", "other"]


# ---------------------------------------------------------------- models
class DepartmentIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class Department(BaseModel):
    id: UUID
    name: str
    course_count: int
    created_at: datetime
    updated_at: datetime


class CourseCreate(BaseModel):
    code: str = Field(min_length=1, max_length=20, examples=["DS 252"])
    name: str = Field(min_length=1, max_length=200)


class CourseUpdate(BaseModel):
    code: str | None = Field(None, min_length=1, max_length=20)
    name: str | None = Field(None, min_length=1, max_length=200)


class Course(BaseModel):
    id: UUID
    department_id: UUID
    code: str
    name: str
    material_count: int
    feedback_count: int
    has_content: bool = Field(description="False means show 'No data yet' (FR-11)")
    created_at: datetime
    updated_at: datetime


class MaterialCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    material_type: MaterialType = "other"
    s3_key: str = Field(description="From POST /uploads with kind=course_material and this course_id")


class MaterialUpdate(BaseModel):
    title: str | None = Field(None, min_length=1, max_length=200)
    material_type: MaterialType | None = None


class Material(BaseModel):
    id: UUID
    course_id: UUID
    title: str
    material_type: MaterialType
    download_url: str
    uploaded_by: UserRef
    created_at: datetime
    updated_at: datetime


class FeedbackIn(BaseModel):
    content: str = Field(min_length=1, max_length=5000)


class Feedback(BaseModel):
    id: UUID
    course_id: UUID
    author: UserRef
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
    return [Department(**dict(r)) for r in await conn.fetch(_DEPT_SELECT + " ORDER BY d.name")]


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
       (SELECT count(*) FROM course_materials m WHERE m.course_id = c.id AND m.deleted_at IS NULL) AS material_count,
       (SELECT count(*) FROM course_feedback f WHERE f.course_id = c.id AND f.deleted_at IS NULL) AS feedback_count
FROM courses c
"""


def _course(r: asyncpg.Record) -> Course:
    return Course(**dict(r), has_content=(r["material_count"] + r["feedback_count"]) > 0)


async def _course_department(conn: asyncpg.Connection, course_id: UUID) -> UUID:
    department_id = await conn.fetchval("SELECT department_id FROM courses WHERE id = $1", course_id)
    if department_id is None:
        raise not_found("Course")
    return department_id


@router.get("/departments/{department_id}/courses", response_model=list[Course],
            summary="Courses in a department, with whether each has content (FR-11)")
async def list_courses(department_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM departments WHERE id = $1)", department_id):
        raise not_found("Department")
    rows = await conn.fetch(_COURSE_SELECT + " WHERE c.department_id = $1 ORDER BY c.code", department_id)
    return [_course(r) for r in rows]


@router.get("/courses/{course_id}", response_model=Course, summary="One course")
async def get_course(course_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    r = await conn.fetchrow(_COURSE_SELECT + " WHERE c.id = $1", course_id)
    if r is None:
        raise not_found("Course")
    return _course(r)


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


# ---------------------------------------------------------------- materials
_MATERIAL_SELECT = """
SELECT m.id, m.course_id, m.title, m.material_type::text AS material_type, m.file_s3_key,
       m.created_at, m.updated_at, u.id AS uploader_id, u.name AS uploader_name
FROM course_materials m JOIN users u ON u.id = m.uploaded_by
"""


def _material(r: asyncpg.Record) -> Material:
    return Material(id=r["id"], course_id=r["course_id"], title=r["title"], material_type=r["material_type"],
                    download_url=file_url(r["file_s3_key"]),
                    uploaded_by=UserRef(id=r["uploader_id"], name=r["uploader_name"]),
                    created_at=r["created_at"], updated_at=r["updated_at"])


async def _material_course(conn: asyncpg.Connection, material_id: UUID) -> asyncpg.Record:
    row = await conn.fetchrow(
        "SELECT course_id, uploaded_by FROM course_materials WHERE id = $1 AND deleted_at IS NULL", material_id)
    if row is None:
        raise not_found("Material")
    return row


@router.get("/courses/{course_id}/materials", response_model=Page[Material], summary="A course's materials")
async def list_materials(course_id: UUID, material_type: MaterialType | None = None,
                         page: PageParams = Depends(page_params), conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    rows = await conn.fetch(
        _MATERIAL_SELECT + """
        WHERE m.course_id = $1 AND m.deleted_at IS NULL AND ($2::text IS NULL OR m.material_type::text = $2)
        ORDER BY m.created_at DESC LIMIT $3 OFFSET $4""",
        course_id, material_type, page.limit + 1, page.offset)
    return make_page(rows, page, _material)


@router.post("/courses/{course_id}/materials", response_model=Material, status_code=201,
             summary="Add a material (course moderator of this course, department moderator or admin)")
async def create_material(course_id: UUID, body: MaterialCreate, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    if not await can_manage_course(conn, user, course_id):
        raise forbidden("Only moderators of this course or its department can add materials.")
    await verify_own_uploads([body.s3_key], "course_material", user.id, course_id)
    material_id = await conn.fetchval(
        """INSERT INTO course_materials (course_id, uploaded_by, title, material_type, file_s3_key)
           VALUES ($1, $2, $3, $4, $5) RETURNING id""",
        course_id, user.id, body.title.strip(), body.material_type, body.s3_key)
    return _material(await conn.fetchrow(_MATERIAL_SELECT + " WHERE m.id = $1", material_id))


@router.patch("/materials/{material_id}", response_model=Material, summary="Edit a material's title or type")
async def update_material(material_id: UUID, body: MaterialUpdate, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    row = await _material_course(conn, material_id)
    if not await can_manage_course(conn, user, row["course_id"]):
        raise forbidden("Only moderators of this course or its department can edit materials.")
    changes = {k: v for k, v in body.model_dump(exclude_unset=True).items() if v is not None}
    sql, values = set_clause(changes, start=2)
    await conn.execute(f"UPDATE course_materials SET {sql} WHERE id = $1", material_id, *values)
    return _material(await conn.fetchrow(_MATERIAL_SELECT + " WHERE m.id = $1", material_id))


@router.delete("/materials/{material_id}", status_code=204, summary="Remove a material")
async def delete_material(material_id: UUID, reason: str | None = Query(None, max_length=500),
                          user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await _material_course(conn, material_id)
    if not await can_manage_course(conn, user, row["course_id"]):
        raise forbidden("Only moderators of this course or its department can remove materials.")
    async with conn.transaction():
        await conn.execute("UPDATE course_materials SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                           material_id, user.id)
        if row["uploaded_by"] != user.id:
            await log_moderation(conn, user.id, "remove_course_material", "course_material", material_id, reason)
    return Response(status_code=204)


# ---------------------------------------------------------------- feedback
_FEEDBACK_SELECT = """
SELECT f.id, f.course_id, f.content, f.created_at, f.updated_at, u.id AS author_id, u.name AS author_name
FROM course_feedback f JOIN users u ON u.id = f.author_id
"""


def _feedback(r: asyncpg.Record) -> Feedback:
    return Feedback(id=r["id"], course_id=r["course_id"], content=r["content"],
                    author=UserRef(id=r["author_id"], name=r["author_name"]),
                    created_at=r["created_at"], updated_at=r["updated_at"])


async def _may_change_feedback(conn: asyncpg.Connection, user: CurrentUser, feedback_id: UUID) -> asyncpg.Record:
    """The author, a moderator of the course's department (scenario 4), or an admin."""
    row = await conn.fetchrow(
        """SELECT f.author_id, c.department_id FROM course_feedback f JOIN courses c ON c.id = f.course_id
           WHERE f.id = $1 AND f.deleted_at IS NULL""", feedback_id)
    if row is None:
        raise not_found("Feedback")
    if row["author_id"] != user.id and not await can_manage_department(conn, user, row["department_id"]):
        raise forbidden("Only the author or this department's moderators can change this feedback.")
    return row


@router.get("/courses/{course_id}/feedback", response_model=Page[Feedback], summary="A course's feedback")
async def list_feedback(course_id: UUID, page: PageParams = Depends(page_params),
                        conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    rows = await conn.fetch(
        _FEEDBACK_SELECT + """ WHERE f.course_id = $1 AND f.deleted_at IS NULL
        ORDER BY f.created_at DESC LIMIT $2 OFFSET $3""", course_id, page.limit + 1, page.offset)
    return make_page(rows, page, _feedback)


@router.post("/courses/{course_id}/feedback", response_model=Feedback, status_code=201,
             summary="Post feedback on a course (FR-12)")
async def create_feedback(course_id: UUID, body: FeedbackIn, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    await _course_department(conn, course_id)
    feedback_id = await conn.fetchval(
        "INSERT INTO course_feedback (course_id, author_id, content) VALUES ($1, $2, $3) RETURNING id",
        course_id, user.id, body.content.strip())
    return _feedback(await conn.fetchrow(_FEEDBACK_SELECT + " WHERE f.id = $1", feedback_id))


@router.patch("/feedback/{feedback_id}", response_model=Feedback, summary="Edit feedback")
async def update_feedback(feedback_id: UUID, body: FeedbackIn, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    await _may_change_feedback(conn, user, feedback_id)
    await conn.execute("UPDATE course_feedback SET content = $2 WHERE id = $1", feedback_id, body.content.strip())
    return _feedback(await conn.fetchrow(_FEEDBACK_SELECT + " WHERE f.id = $1", feedback_id))


@router.delete("/feedback/{feedback_id}", status_code=204, summary="Remove feedback")
async def delete_feedback(feedback_id: UUID, reason: str | None = Query(None, max_length=500),
                          user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await _may_change_feedback(conn, user, feedback_id)
    async with conn.transaction():
        await conn.execute("UPDATE course_feedback SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                           feedback_id, user.id)
        if row["author_id"] != user.id:
            await log_moderation(conn, user.id, "remove_course_feedback", "course_feedback", feedback_id, reason)
    return Response(status_code=204)
