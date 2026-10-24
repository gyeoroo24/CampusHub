"""My notifications inbox and push-notification devices (FR-9, FR-22)."""
from datetime import datetime
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user
from ..common import Page, PageParams, make_page, page_params
from ..db import get_conn

router = APIRouter(prefix="/me", tags=["Notifications"])


class Notification(BaseModel):
    id: UUID
    type: str
    payload: dict
    is_read: bool
    created_at: datetime


class DeviceIn(BaseModel):
    platform: Literal["android", "ios", "web", "desktop"]
    push_token: str = Field(min_length=1, max_length=4096, description="Token from FCM / APNs / Web Push")


class DeviceToken(BaseModel):
    push_token: str = Field(min_length=1, max_length=4096)


@router.get("/notifications", response_model=Page[Notification], summary="My notifications, newest first")
async def list_notifications(unread_only: bool = False, page: PageParams = Depends(page_params),
                             user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(
        """SELECT id, type::text AS type, payload, is_read, created_at FROM notifications
           WHERE user_id = $1 AND (NOT $2 OR NOT is_read)
           ORDER BY created_at DESC, id DESC LIMIT $3 OFFSET $4""",
        user.id, unread_only, page.limit + 1, page.offset)
    return make_page(rows, page, lambda r: Notification(**dict(r)))


@router.post("/notifications/{notification_id}/read", status_code=204, summary="Mark one notification read")
async def mark_read(notification_id: UUID, user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    await conn.execute("UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2",
                       notification_id, user.id)
    return Response(status_code=204)


@router.post("/notifications/read-all", summary="Mark all my notifications read")
async def mark_all_read(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)) -> dict:
    result = await conn.execute("UPDATE notifications SET is_read = true WHERE user_id = $1 AND NOT is_read", user.id)
    return {"updated": int(result.split()[-1])}


@router.post("/devices", status_code=204, summary="Register this device for push notifications")
async def register_device(body: DeviceIn, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    # A token is unique per device: if another account used this device, it moves to the current user.
    await conn.execute(
        """INSERT INTO push_devices (user_id, platform, push_token) VALUES ($1, $2, $3)
           ON CONFLICT (push_token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform""",
        user.id, body.platform, body.push_token)
    return Response(status_code=204)


@router.delete("/devices", status_code=204, summary="Stop push notifications to this device (call on sign-out)")
async def unregister_device(body: DeviceToken, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
    # The token travels in the body, not the URL, so it doesn't end up in access logs.
    await conn.execute("DELETE FROM push_devices WHERE push_token = $1 AND user_id = $2", body.push_token, user.id)
    return Response(status_code=204)
