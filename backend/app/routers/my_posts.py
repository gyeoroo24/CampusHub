"""What I've posted outside Buy & Sell and Lost & Found, for the "My postings" section of my profile.

  everyone            my course feedback and my uploaded course materials
  moderators / admin  also the companies and the events and mess menus I added (others have none, so their
                      lists are simply empty)

Buy & Sell, Wanted and Lost & Found have their own "mine" filters (seller_id, reporter_id, /me/wanted).
"""
from datetime import date, datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..auth import CurrentUser, current_user
from ..db import get_conn

router = APIRouter(tags=["Users"])

LIMIT = 200


class MyFeedback(BaseModel):
    id: UUID
    course_id: UUID
    course_code: str
    course_name: str
    content: str
    is_anonymous: bool
    created_at: datetime


class MyMaterial(BaseModel):
    id: UUID
    course_id: UUID
    course_code: str
    course_name: str
    title: str
    material_type: str
    held: bool
    created_at: datetime


class MyCompany(BaseModel):
    id: UUID
    name: str
    industry: str | None
    created_at: datetime


class MyEvent(BaseModel):
    id: UUID
    title: str
    location: str | None
    start_time: datetime
    end_time: datetime
    created_at: datetime


class MyMessMenu(BaseModel):
    id: UUID
    mess_id: int
    mess_name: str
    valid_from: date
    valid_to: date
    created_at: datetime


class MyPosts(BaseModel):
    feedback: list[MyFeedback]
    materials: list[MyMaterial]
    companies: list[MyCompany]
    events: list[MyEvent]
    mess_menus: list[MyMessMenu]


@router.get("/me/posts", response_model=MyPosts,
            summary="My course feedback and materials, and the companies, events and mess menus I added")
async def my_posts(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    """Newest first, at most 200 of each. Removed items are left out."""
    feedback = await conn.fetch(
        """SELECT f.id, f.course_id, c.code AS course_code, c.name AS course_name, f.content, f.is_anonymous,
                  f.created_at
             FROM course_feedback f JOIN courses c ON c.id = f.course_id
            WHERE f.author_id = $1 AND f.deleted_at IS NULL
            ORDER BY f.created_at DESC LIMIT $2""", user.id, LIMIT)
    materials = await conn.fetch(
        """SELECT m.id, m.course_id, c.code AS course_code, c.name AS course_name, m.title,
                  m.material_type::text AS material_type, m.held_for_review_at IS NOT NULL AS held, m.created_at
             FROM course_materials m JOIN courses c ON c.id = m.course_id
            WHERE m.uploaded_by = $1 AND m.deleted_at IS NULL
            ORDER BY m.created_at DESC LIMIT $2""", user.id, LIMIT)
    companies = await conn.fetch(
        """SELECT id, name, industry, created_at FROM companies WHERE created_by = $1
            ORDER BY created_at DESC LIMIT $2""", user.id, LIMIT)
    events = await conn.fetch(
        """SELECT id, title, location, start_time, end_time, created_at FROM events
            WHERE created_by = $1 AND deleted_at IS NULL
            ORDER BY start_time DESC LIMIT $2""", user.id, LIMIT)
    menus = await conn.fetch(
        """SELECT mm.id, mm.mess_id, ms.name AS mess_name, mm.valid_from, mm.valid_to, mm.created_at
             FROM mess_menus mm JOIN messes ms ON ms.id = mm.mess_id
            WHERE mm.created_by = $1
            ORDER BY mm.valid_from DESC LIMIT $2""", user.id, LIMIT)
    return MyPosts(feedback=[MyFeedback(**dict(r)) for r in feedback],
                   materials=[MyMaterial(**dict(r)) for r in materials],
                   companies=[MyCompany(**dict(r)) for r in companies],
                   events=[MyEvent(**dict(r)) for r in events],
                   mess_menus=[MyMessMenu(**dict(r)) for r in menus])
