"""Campus services ("Taking it further", rev 6): Health Centre, Wellness Centre and grievance
links for the landing page. Everyone can read the list; only the admin changes it, so a new
link or phone number needs no app release. Initial rows: db/reference-data.sql.
"""
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, StringConstraints, model_validator

from ..auth import CurrentUser, current_user, optional_user
from ..common import forbidden, not_found, set_clause, text
from ..db import get_conn

router = APIRouter(prefix="/campus-services", tags=["Campus services"])

Category = Literal["health", "wellbeing", "grievance", "safety", "other"]
Url = Annotated[str, StringConstraints(strip_whitespace=True, max_length=500, pattern=r"^https?://\S+$")]
Phone = Annotated[str, StringConstraints(strip_whitespace=True, pattern=r"^\+?[0-9 -]{3,20}$")]


class ServiceCreate(BaseModel):
    name: text(80)
    description: text(300, min_length=0) | None = None
    category: Category
    url: Url | None = None
    phone: Phone | None = None
    sort_order: int = Field(100, ge=0, le=1000, description="Lower comes first within its category")
    is_active: bool = True

    @model_validator(mode="after")
    def _contact(self):
        if self.url is None and self.phone is None:
            raise ValueError("give a url, a phone number, or both")
        return self


class ServiceUpdate(BaseModel):
    name: text(80) | None = None
    description: text(300, min_length=0) | None = None
    category: Category | None = None
    url: Url | None = None
    phone: Phone | None = None
    sort_order: int | None = Field(None, ge=0, le=1000)
    is_active: bool | None = Field(None, description="false hides it from the landing page without deleting it")


class Service(BaseModel):
    id: UUID
    name: str
    description: str | None
    category: Category
    url: str | None
    phone: str | None
    sort_order: int
    is_active: bool
    updated_at: datetime


_SELECT = """SELECT id, name, description, category::text AS category, url, phone, sort_order, is_active, updated_at
             FROM campus_services"""
_ORDER = " ORDER BY array_position(enum_range(NULL::campus_service_category), category), sort_order, name"


def _require_admin(user: CurrentUser) -> None:
    if not user.is_admin:
        raise forbidden("Only the admin can change campus services.")


@router.get("", response_model=list[Service],
            summary="Campus services for the landing page, grouped by category (guests allowed)")
async def list_services(include_inactive: bool = False, viewer: CurrentUser | None = Depends(optional_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    show_all = include_inactive and viewer is not None and viewer.is_admin
    rows = await conn.fetch(_SELECT + " WHERE $1 OR is_active" + _ORDER, show_all)
    return [Service(**dict(r)) for r in rows]


@router.post("", response_model=Service, status_code=201, summary="Add a campus service (admin)")
async def create_service(body: ServiceCreate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    _require_admin(user)
    row = await conn.fetchrow(
        """INSERT INTO campus_services (name, description, category, url, phone, sort_order, is_active)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id, name, description, category::text AS category, url, phone, sort_order, is_active, updated_at""",
        body.name, body.description, body.category, body.url, body.phone, body.sort_order, body.is_active)
    return Service(**dict(row))


@router.patch("/{service_id}", response_model=Service, summary="Edit a campus service (admin)")
async def update_service(service_id: UUID, body: ServiceUpdate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    _require_admin(user)
    changes = body.model_dump(exclude_unset=True)
    for required in ("name", "category", "sort_order", "is_active"):
        if required in changes and changes[required] is None:
            raise HTTPException(422, f"{required} can't be empty.")
    sql, values = set_clause(changes, start=2)
    try:
        row = await conn.fetchrow(
            f"""UPDATE campus_services SET {sql} WHERE id = $1
                RETURNING id, name, description, category::text AS category, url, phone, sort_order, is_active,
                          updated_at""", service_id, *values)
    except asyncpg.CheckViolationError as exc:
        raise HTTPException(422, "A service needs a url or a phone number.") from exc
    if row is None:
        raise not_found("Campus service")
    return Service(**dict(row))


@router.delete("/{service_id}", status_code=204, summary="Delete a campus service (admin)")
async def delete_service(service_id: UUID, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    _require_admin(user)
    deleted = await conn.execute("DELETE FROM campus_services WHERE id = $1", service_id)
    if deleted.endswith(" 0"):
        raise not_found("Campus service")
    return Response(status_code=204)
