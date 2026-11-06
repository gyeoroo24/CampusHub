"""Matcher Lambda entry point (image: Dockerfile.matcher, handler app.matching.handler.handler).

Events:
  {"kind": "lost" | "found", "report_id": "<uuid>"}   sent by the API on every relevant change
  {"backfill": true}                                   match every report still pending
  {"screen": "listing" | "lost_report" | "found_report", "id": "<uuid>"}
                                                       check the post's photos for obscene images
The models stay loaded in a warm container; the database pool is closed after each event, as
in app/jobs.py.
"""
import asyncio
import logging
from uuid import UUID

from ..db import close_pool
from .engine import backfill, run_one
from .trigger import get_embedder, get_nsfw_classifier

logging.getLogger("campushub").setLevel(logging.INFO)


async def _handle(event: dict) -> dict:
    try:
        if event.get("screen") in ("listing", "lost_report", "found_report"):
            from .photo_screen import run_photo_screen
            classifier = get_nsfw_classifier()
            if classifier is None:
                raise RuntimeError("The obscene-photo model is missing from this image")
            await run_photo_screen(event["screen"], UUID(event["id"]), classifier)
            return {"screened": 1}
        embedder = get_embedder()
        if event.get("backfill"):
            return {"matched": await backfill(embedder)}
        if event.get("kind") not in ("lost", "found"):
            raise ValueError(f"Unknown event: {event!r}")
        await run_one(event["kind"], UUID(event["report_id"]), embedder)
        return {"matched": 1}
    finally:
        await close_pool()


def handler(event, context):
    return asyncio.run(_handle(event))
