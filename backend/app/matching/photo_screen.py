"""Obscene-photo screening of new posts (future plan §1.6): the image half of app/screening.py.

Runs where Lost & Found matching runs (matcher Lambda, or a background task locally), because it
needs the 87 MB image model; files the same automatic report through app.screening.flag().
"""
import asyncio
import logging
from uuid import UUID

import asyncpg

from ..db import get_pool
from ..notify import deliver_push
from ..screening import flag
from .engine import _fetch_photo
from .nsfw import FLAG_AT

log = logging.getLogger("campushub.matching")

PHOTOS = {"listing": ("listing_photos", "listing_id"),
          "lost_report": ("lost_report_photos", "lost_report_id"),
          "found_report": ("found_report_photos", "found_report_id")}


async def screen_photos(conn: asyncpg.Connection, kind: str, item_id: UUID, classifier) -> bool:
    """Flag the post if any of its photos looks obscene. Returns True if it was flagged."""
    table, fk = PHOTOS[kind]
    keys = [r["s3_key"] for r in await conn.fetch(
        f"SELECT s3_key FROM {table} WHERE {fk} = $1 ORDER BY sort_order", item_id)]
    flagged = 0
    for key in keys:
        data = await _fetch_photo(key)
        if data is None:
            continue
        p = await asyncio.to_thread(classifier.probability, data)
        if p is not None and p >= FLAG_AT:
            flagged += 1
    if not flagged:
        return False
    async with conn.transaction():
        return await flag(conn, None, kind, item_id,
                          [f"possible obscene photo ({flagged} of {len(keys)})"])


async def run_photo_screen(kind: str, item_id: UUID, classifier) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        flagged = await screen_photos(conn, kind, item_id, classifier)
        owner = None
        if flagged:
            owner = await conn.fetchval(
                f"SELECT {'seller_id' if kind == 'listing' else 'reporter_id'} FROM {kind}s WHERE id = $1", item_id)
    if owner:
        await deliver_push([owner], "moderation_action", {"message": "One of your posts was flagged for review."})
