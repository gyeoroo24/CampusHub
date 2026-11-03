"""Meal alerts: shortly before each meal, people who follow a mess get that day's dishes.

A mess's menu (mess_menus + mess_menu_items) says what each meal has on each weekday, and it repeats
every week from valid_from to valid_to. send_due_meal_alerts() runs every few minutes (the
meal-alerts Lambda on an EventBridge schedule, or the API's own loop locally; see app/jobs.py). For
each meal starting within the next ALERT_LEAD it sends one in-app notification (type mess_menu) per
follower who chose that meal, then records it in mess_alerts_sent so the next run doesn't repeat it.
A run that is late by up to ALERT_GRACE after the meal started still sends; later than that it skips.

The clock that sends them: every open app asks for its notifications once a minute, and that request
also sends whatever is due (send_due_if_stale, at most once a minute per server), so no separate job
is needed while people use the app. The scheduled job (app/jobs.py) is a backup for quiet hours,
when nobody's app is open to trigger it.

A menu posted only as a PDF or photo (no dishes typed in) still alerts: "Lunch at 12:30 pm; see
today's menu" instead of the dishes.
"""
import logging
from datetime import date, datetime, time, timedelta, timezone
from time import monotonic

import asyncpg

from .config import get_settings
from .notify import create_notifications, deliver_push

log = logging.getLogger("campushub.mess_alerts")

IST = timezone(timedelta(hours=5, minutes=30), "IST")
MEALS = ("breakfast", "lunch", "snacks", "dinner")
MEAL_NAMES = {"breakfast": "Breakfast", "lunch": "Lunch", "snacks": "Snacks", "dinner": "Dinner"}
ALERT_LEAD = timedelta(minutes=30)
ALERT_GRACE = timedelta(minutes=30)


def meal_message(mess: str, meal: str, starts: time, items: str | None) -> str:
    at = f"{mess} · {MEAL_NAMES[meal]} at {starts.strftime('%-I:%M %p').lower()} today"
    return f"{at}: {items}" if items else f"{at}. Tap to see the menu."


async def due_meals(conn: asyncpg.Connection, now: datetime) -> list[asyncpg.Record]:
    """Meals of today (India time) whose alert is due and not sent yet, with that day's dishes."""
    local = now.astimezone(IST)
    today = local.date()
    rows = await conn.fetch(
        """SELECT m.id AS mess_id, m.name, x.meal, i.items, mm.id AS menu_id,
                  CASE x.meal WHEN 'breakfast' THEN m.breakfast_at WHEN 'lunch' THEN m.lunch_at
                              WHEN 'snacks' THEN m.snacks_at ELSE m.dinner_at END AS starts
           FROM messes m
           JOIN mess_menus mm ON mm.mess_id = m.id AND $1::date BETWEEN mm.valid_from AND mm.valid_to
           CROSS JOIN unnest(ARRAY['breakfast', 'lunch', 'snacks', 'dinner']) AS x(meal)
           LEFT JOIN mess_menu_items i ON i.menu_id = mm.id AND i.weekday = $2 AND i.meal = x.meal
           -- a meal that has dishes today, or any meal when the menu is only a file
           WHERE (i.items IS NOT NULL OR NOT EXISTS (SELECT 1 FROM mess_menu_items y WHERE y.menu_id = mm.id))
             AND NOT EXISTS (SELECT 1 FROM mess_alerts_sent s
                             WHERE s.mess_id = m.id AND s.day = $1::date AND s.meal = x.meal)""",
        today, today.isoweekday())
    due = []
    for r in rows:
        starts = datetime.combine(today, r["starts"], tzinfo=IST)
        if starts - ALERT_LEAD <= local <= starts + ALERT_GRACE:
            due.append(r)
    return due


async def send_due_meal_alerts(conn: asyncpg.Connection, now: datetime | None = None) -> list[tuple[str, str, int]]:
    """Send every alert that is due. Returns (mess, meal, recipients) for each meal sent."""
    now = now or datetime.now(timezone.utc)
    today: date = now.astimezone(IST).date()
    sent = []
    for r in await due_meals(conn, now):
        async with conn.transaction():
            # Claim the meal first, so two overlapping runs can't both send it.
            claimed = await conn.fetchval(
                """INSERT INTO mess_alerts_sent (mess_id, day, meal, recipients) VALUES ($1, $2, $3, 0)
                   ON CONFLICT DO NOTHING RETURNING true""", r["mess_id"], today, r["meal"])
            if not claimed:
                continue
            followers = [f["user_id"] for f in await conn.fetch(
                "SELECT user_id FROM mess_follows WHERE mess_id = $1 AND $2 = ANY(meals)", r["mess_id"], r["meal"])]
            payload = {"mess_id": r["mess_id"], "mess": r["name"], "meal": r["meal"], "day": today.isoformat(),
                       "menu_id": str(r["menu_id"]),
                       "message": meal_message(r["name"], r["meal"], r["starts"], r["items"])}
            recipients = await create_notifications(conn, followers, "mess_menu", payload)
            await conn.execute("UPDATE mess_alerts_sent SET recipients = $4 WHERE mess_id = $1 AND day = $2 AND meal = $3",
                               r["mess_id"], today, r["meal"], len(recipients))
        await deliver_push(recipients, "mess_menu", payload)
        log.info("Meal alert: %s %s to %d followers", r["name"], r["meal"], len(recipients))
        sent.append((r["name"], r["meal"], len(recipients)))
    return sent


CHECK_EVERY_SECONDS = 60
_last_check = 0.0


async def send_due_if_stale(conn: asyncpg.Connection) -> None:
    """Called from requests the app makes every minute: sends the alerts that are due, at most once a
    minute per server. Never fails the request it rides on."""
    global _last_check
    if not get_settings().meal_alerts_on_requests:
        return
    now = monotonic()
    if now - _last_check < CHECK_EVERY_SECONDS:
        return
    _last_check = now
    try:
        await send_due_meal_alerts(conn)
    except Exception:  # noqa: BLE001
        log.exception("Meal alert check failed")
