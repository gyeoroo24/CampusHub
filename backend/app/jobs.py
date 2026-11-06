"""Scheduled jobs.

meal_alerts_handler sends the mess meal alerts that are due (app/mess_alerts.py). Deploy it as a
Lambda function from the same image with handler app.jobs.meal_alerts_handler, triggered every 5
minutes by an EventBridge schedule. Locally: python -m app.jobs meals, or set
CAMPUSHUB_MEAL_ALERT_POLL_SECONDS so the API checks by itself.

purge_handler deletes in-app notifications older than 30 days (the inbox keeps short-lived
rows; see the notifications table in schema.sql). Deploy it as a second Lambda function from
the same image with handler app.jobs.purge_handler, triggered daily by an EventBridge schedule.
Locally: python -m app.jobs
"""
import asyncio
import logging

from .db import close_pool, get_pool
from .mess_alerts import send_due_meal_alerts

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


async def run_meal_alerts() -> list[tuple[str, str, int]]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        return await send_due_meal_alerts(conn)


async def _run_meal_alerts() -> list[tuple[str, str, int]]:
    try:
        return await run_meal_alerts()
    finally:
        await close_pool()


def meal_alerts_handler(event, context):
    """Lambda entry point for the 5-minute EventBridge schedule."""
    sent = asyncio.run(_run_meal_alerts())
    return {"sent": [{"mess": m, "meal": meal, "recipients": n} for m, meal, n in sent]}


async def meal_alert_loop(every_seconds: int) -> None:
    """The API's own checker, for running without EventBridge (local development, EC2)."""
    while True:
        try:
            await run_meal_alerts()
        except Exception:  # noqa: BLE001 - keep checking; one bad run mustn't stop the alerts
            log.exception("Meal alert run failed")
        await asyncio.sleep(every_seconds)


if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO)
    print(meal_alerts_handler({}, None) if sys.argv[1:] == ["meals"] else purge_handler({}, None))
