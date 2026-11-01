"""Alerts for new items: saved searches and Wanted posts ("Taking it further", rev 6).

A saved search watches new listings (buy_sell) or new found reports (lost_found) with the same
filters as GET /listings and GET /found-reports. A Wanted post watches new listings in its
category, within its budget, that share a word with its title. Whoever matches gets one
notification per item: the item's id in the notification payload is the dedupe key, as with
FR-9, so editing a listing never alerts the same person twice.

The functions run inside the request's transaction (inbox rows roll back with it) and return
the pushes to send once the response is out; see push_alerts.
"""
from uuid import UUID

import asyncpg
from fastapi import BackgroundTasks

from .notify import create_notifications, deliver_push

Push = tuple[list[UUID], str, dict]

# Does listing l match saved search s? Same rules as GET /listings.
# A search with no keyword, category or price (allowed before 2 Nov 2026) matches nothing: it used
# to alert on every new post, e.g. "Drugs" for a search named "hero cycle".
LISTING_MATCHES_SEARCH = """
    (s.query IS NOT NULL OR s.bs_category_id IS NOT NULL OR s.min_price IS NOT NULL OR s.max_price IS NOT NULL)
    AND (s.bs_category_id IS NULL OR s.bs_category_id = l.category_id)
    AND (s.min_price IS NULL OR l.price >= s.min_price)
    AND (s.max_price IS NULL OR l.price <= s.max_price)
    AND (s.query IS NULL OR numnode(websearch_to_tsquery('english', s.query)) = 0
         OR l.search_vector @@ websearch_to_tsquery('english', s.query))
"""

# Does found report f match saved search s? Same rules as GET /found-reports (substring of the description).
FOUND_MATCHES_SEARCH = r"""
    (s.query IS NOT NULL OR s.lf_category_id IS NOT NULL)
    AND (s.lf_category_id IS NULL OR s.lf_category_id = f.category_id)
    AND (s.query IS NULL OR f.description ILIKE
         '%' || replace(replace(replace(s.query, '\', '\\'), '%', '\%'), '_', '\_') || '%' ESCAPE '\')
"""

# Does listing l match Wanted post w? Same category, within budget, and at least one word of the
# title in the listing (any word, so "Need a Hero cycle" matches "Hero Sprint 26T").
LISTING_MATCHES_WANTED = """
    w.category_id = l.category_id
    AND (w.max_price IS NULL OR l.price <= w.max_price)
    AND (numnode(plainto_tsquery('english', w.title)) = 0
         OR l.search_vector @@ replace(plainto_tsquery('english', w.title)::text, ' & ', ' | ')::tsquery)
"""


def _rupees(price) -> str:
    return f"₹{price:,.0f}"


async def listing_alerts(conn: asyncpg.Connection, listing_id: UUID) -> list[Push]:
    """A listing was created, or changed so it may match more searches. Alerts saved-search owners
    and Wanted-post authors who haven't been told about it yet."""
    pushes: list[Push] = []
    rows = await conn.fetch(
        f"""SELECT DISTINCT ON (s.user_id) s.user_id, s.id AS search_id, s.name, l.title, l.price
            FROM listings l JOIN saved_searches s ON s.module = 'buy_sell' AND s.alerts_enabled
            WHERE l.id = $1 AND l.deleted_at IS NULL AND l.status = 'available' AND s.user_id <> l.seller_id
              AND {LISTING_MATCHES_SEARCH}
              AND NOT EXISTS (SELECT 1 FROM notifications n
                              WHERE n.user_id = s.user_id AND n.type = 'saved_search_match'
                                AND n.payload->>'listing_id' = $1::text)
            ORDER BY s.user_id, s.created_at""", listing_id)
    for r in rows:
        payload = {"listing_id": str(listing_id), "saved_search_id": str(r["search_id"]),
                   "message": f"New match for “{r['name']}”: {r['title']} for {_rupees(r['price'])}"}
        pushes.append((await create_notifications(conn, [r["user_id"]], "saved_search_match", payload),
                       "saved_search_match", payload))
    rows = await conn.fetch(
        f"""SELECT DISTINCT ON (w.author_id) w.author_id, w.id AS wanted_id, w.title AS wanted_title,
                   l.title, l.price
            FROM listings l JOIN wanted_posts w ON w.status = 'open' AND w.deleted_at IS NULL
            WHERE l.id = $1 AND l.deleted_at IS NULL AND l.status = 'available' AND w.author_id <> l.seller_id
              AND {LISTING_MATCHES_WANTED}
              AND NOT EXISTS (SELECT 1 FROM notifications n
                              WHERE n.user_id = w.author_id AND n.type = 'wanted_post_match'
                                AND n.payload->>'listing_id' = $1::text)
            ORDER BY w.author_id, w.created_at DESC""", listing_id)
    for r in rows:
        payload = {"listing_id": str(listing_id), "wanted_post_id": str(r["wanted_id"]),
                   "message": f"Someone listed {r['title']} for {_rupees(r['price'])}, "
                              f"which may be what you wanted (“{r['wanted_title']}”)"}
        pushes.append((await create_notifications(conn, [r["author_id"]], "wanted_post_match", payload),
                       "wanted_post_match", payload))
    return pushes


async def found_report_alerts(conn: asyncpg.Connection, found_report_id: UUID) -> list[Push]:
    """A found report was filed, or changed so it may match more saved Lost & Found searches."""
    rows = await conn.fetch(
        f"""SELECT DISTINCT ON (s.user_id) s.user_id, s.id AS search_id, s.name, c.name AS category
            FROM found_reports f JOIN lf_categories c ON c.id = f.category_id
            JOIN saved_searches s ON s.module = 'lost_found' AND s.alerts_enabled
            WHERE f.id = $1 AND f.deleted_at IS NULL AND f.status = 'open' AND s.user_id <> f.reporter_id
              AND {FOUND_MATCHES_SEARCH}
              AND NOT EXISTS (SELECT 1 FROM notifications n
                              WHERE n.user_id = s.user_id AND n.type = 'saved_search_match'
                                AND n.payload->>'found_report_id' = $1::text)
            ORDER BY s.user_id, s.created_at""", found_report_id)
    pushes: list[Push] = []
    for r in rows:
        payload = {"found_report_id": str(found_report_id), "saved_search_id": str(r["search_id"]),
                   "message": f"New match for “{r['name']}”: someone found a {r['category']}"}
        pushes.append((await create_notifications(conn, [r["user_id"]], "saved_search_match", payload),
                       "saved_search_match", payload))
    return pushes


def push_alerts(background: BackgroundTasks, pushes: list[Push]) -> None:
    """Send the pushes after the response (call once the transaction has committed)."""
    for user_ids, notification_type, payload in pushes:
        background.add_task(deliver_push, user_ids, notification_type, payload)
