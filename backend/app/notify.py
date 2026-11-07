"""Notifications: an in-app inbox row per user, plus push to their registered devices.

Inbox rows are written inside the request's transaction. Push delivery runs as a
background task after the response, so a rolled-back request never sends a push.
On Lambda (Mangum) background tasks finish before the invocation returns, so their time
counts towards the response; push_timeout_seconds caps it. Moving pushes to a queue (SQS)
would take them off the response path entirely.

Push sending is pluggable. WebPushSender delivers to browsers (FR-22, app/webpush.py) when a VAPID
key is configured; otherwise LogPushSender only logs. Native apps (FCM / APNs, see
push_devices.sns_endpoint_arn) would get a sender of their own.
"""
import asyncio
import json
import logging
from functools import lru_cache
from typing import Protocol
from uuid import UUID

import asyncpg

from . import webpush
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


_TITLES = {
    "lost_found_match": "Possible match for your item",
    "forum_reply": "New reply",
    "listing_status_change": "Listing update",
    "bookmarked_event_update": "Event update",
    "followed_tag_event": "New event",
    "moderation_action": "From the moderators",
    "saved_search_match": "New listing for your saved search",
    "wanted_post_match": "Someone is selling what you want",
    "chat_message": "New message",
    "listing_watch": "Price update",
    "mess_menu": "Mess menu",
    "course_update": "Course update",
}


def push_message(notification_type: str, payload: dict) -> dict:
    """What the browser shows: a title, the inbox message, and the page a tap opens."""
    if payload.get("conversation_id"):
        url = f"/messages/{payload['conversation_id']}"
    elif payload.get("listing_id"):
        url = f"/buy/{payload['listing_id']}"
    elif payload.get("event_id"):
        url = f"/events/{payload['event_id']}"
    elif payload.get("course_id"):
        url = f"/courses/{payload['course_id']}"
    elif payload.get("mess_id"):
        url = f"/mess?mess={payload['mess_id']}"
    elif notification_type == "lost_found_match" or payload.get("found_report_id"):
        url = "/lost-found"
    else:
        url = "/buy"
    return {"title": _TITLES.get(notification_type, "CampusHub"),
            "body": str(payload.get("message") or "You have a new notification."),
            "url": url, "tag": notification_type}


@lru_cache
def _ssm_parameter(name: str) -> str:
    import boto3
    return boto3.client("ssm").get_parameter(Name=name)["Parameter"]["Value"]


def push_public_key() -> str | None:
    """The VAPID public key browsers subscribe with, or None if push isn't set up here."""
    s = get_settings()
    if s.vapid_public_key:
        return s.vapid_public_key
    if s.vapid_private_key:
        return webpush.public_key_of(s.vapid_private_key)
    if s.vapid_public_key_parameter:
        try:
            return _ssm_parameter(s.vapid_public_key_parameter)
        except Exception:  # noqa: BLE001 - the key not being created yet just means push is off
            log.warning("No VAPID public key in SSM at %s; push is off", s.vapid_public_key_parameter)
    return None


class WebPushSender:
    """Browsers' Web Push subscriptions (platform "web"). Subscriptions the push service reports as gone
    are deleted."""

    async def send(self, devices: list[asyncpg.Record], notification_type: str, payload: dict) -> None:
        tokens = [d["push_token"] for d in devices if d["platform"] == "web"]
        if not tokens:
            return
        message = push_message(notification_type, payload)
        s = get_settings()
        if s.push_sender_function:
            gone = await asyncio.to_thread(_invoke_sender, s.push_sender_function, tokens, message)
        else:
            vapid = webpush.VapidKey(s.vapid_private_key, s.vapid_subject)
            gone = await asyncio.to_thread(webpush.send_all, vapid, tokens, message)
        if gone:
            pool = await get_pool()
            async with pool.acquire() as conn:
                await conn.execute("DELETE FROM push_devices WHERE push_token = ANY($1::text[])", gone)


@lru_cache
def _lambda_client():
    import boto3
    return boto3.client("lambda")


def _invoke_sender(function: str, tokens: list[str], message: dict) -> list[str]:
    response = _lambda_client().invoke(FunctionName=function,
                                       Payload=json.dumps({"tokens": tokens, "message": message}).encode())
    result = json.loads(response["Payload"].read() or b"{}")
    if response.get("FunctionError"):
        log.error("Push sender failed: %s", result)
        return []
    return list(result.get("gone", []))


def push_enabled() -> bool:
    s = get_settings()
    return bool(s.vapid_private_key or (s.push_sender_function and push_public_key()))


# None: decided on first use from the settings (tests may set their own).
push_sender: PushSender | None = None


def _sender() -> PushSender:
    global push_sender
    if push_sender is None:
        push_sender = WebPushSender() if push_enabled() else LogPushSender()
    return push_sender


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
        await asyncio.wait_for(_sender().send(devices, notification_type, payload),
                               timeout=get_settings().push_timeout_seconds)
    except TimeoutError:
        log.error("Push delivery for %s took longer than %ss and was abandoned",
                  notification_type, get_settings().push_timeout_seconds)
    except Exception:  # noqa: BLE001 - a failed push must not surface as an API error
        log.exception("Push delivery failed for %s", notification_type)
