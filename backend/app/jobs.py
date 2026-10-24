"""Scheduled jobs.

purge_handler deletes in-app notifications older than 30 days (the inbox keeps short-lived
rows; see the notifications table in schema.sql). Deploy it as a second Lambda function from
the same image with handler app.jobs.purge_handler, triggered daily by an EventBridge schedule.
Locally: python -m app.jobs
"""
import asyncio
import logging

from .db import close_pool, get_pool

log = logging.getLogger("campushub.jobs")

NOTIFICATION_RETENTION_DAYS = 30


async def purge_notifications(older_than_days: int = NOTIFICATION_RETENTION_DAYS) -> int:
    """Delete notifications older than the given number of days. Returns how many were deleted."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        result = await conn.execute(
            "DELETE FROM notifications WHERE created_at < now() - make_interval(days => $1)", older_than_days)
    deleted = int(result.split()[-1])
    log.info("Purged %d notifications older than %d days", deleted, older_than_days)
    return deleted


async def _run_purge() -> int:
    try:
        return await purge_notifications()
    finally:
        await close_pool()


def purge_handler(event, context):
    """Lambda entry point for the daily EventBridge schedule."""
    return {"deleted": asyncio.run(_run_purge())}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    print(purge_handler({}, None))
