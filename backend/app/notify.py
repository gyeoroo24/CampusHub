"""Notifications: an in-app inbox row per user, plus push to their registered devices.

Inbox rows are written inside the request's transaction. Push delivery runs as a
background task after the response, so a rolled-back request never sends a push.
On Lambda (Mangum) background tasks finish before the invocation returns, so their time
counts towards the response; push_timeout_seconds caps it. Moving pushes to a queue (SQS)
would take them off the response path entirely.

Push sending is pluggable: LogPushSender only logs. Replace it with an SNS / FCM sender
(see push_devices.sns_endpoint_arn) when push is wired up (PRD stretch goal).
"""
import asyncio
import logging
from typing import Protocol
from uuid import UUID

import asyncpg

from .config import get_settings
from .db import get_pool

log = logging.getLogger("campushub.notify")


class PushSender(Protocol):
    async def send(self, devices: list[asyncpg.Record], notification_type: str, payload: dict) -> None: ...


class LogPushSender:
    async def send(self, devices: list[asyncpg.Record], notification_type: str, payload: dict) -> None:
        for d in devices:
            log.info("push %s to %s device of user %s: %s", notification_type, d["platform"], d["user_id"],
                     payload.get("message"))


push_sender: PushSender = LogPushSender()


async def create_notifications(conn: asyncpg.Connection, user_ids: list[UUID],
                               notification_type: str, payload: dict) -> list[UUID]:
    """Insert one inbox row per distinct user. Returns the users notified."""
    recipients = list(dict.fromkeys(user_ids))
    if recipients:
        await conn.executemany(
            "INSERT INTO notifications (user_id, type, payload) VALUES ($1, $2, $3)",
            [(uid, notification_type, payload) for uid in recipients])
    return recipients


async def deliver_push(user_ids: list[UUID], notification_type: str, payload: dict) -> None:
    """Background task: look up the users' devices and hand them to the push sender."""
    if not user_ids:
        return
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            devices = await conn.fetch(
                "SELECT user_id, platform::text AS platform, push_token, sns_endpoint_arn "
                "FROM push_devices WHERE user_id = ANY($1::uuid[])", user_ids)
        await asyncio.wait_for(push_sender.send(devices, notification_type, payload),
                               timeout=get_settings().push_timeout_seconds)
    except TimeoutError:
        log.error("Push delivery for %s took longer than %ss and was abandoned",
                  notification_type, get_settings().push_timeout_seconds)
    except Exception:  # noqa: BLE001 - a failed push must not surface as an API error
        log.exception("Push delivery failed for %s", notification_type)
