"""Start matching for a report that changed. Imported by the API, so it needs nothing beyond the
API's own dependencies: the models (numpy, ONNX Runtime) load only for match_mode "inline".

- "lambda": asynchronously invoke the matcher Lambda (InvocationType=Event). The API adds one
  ~20-50 ms call; the matcher retries on failure, and {"backfill": true} catches anything missed.
- "inline": run app.matching.engine in a background task in this process (local development).
- "off":    nothing; the API keeps the old same-category rule (app/routers/lost_found.py).
"""
import asyncio
import importlib.util
import json
import logging
from functools import lru_cache
from pathlib import Path
from typing import Literal
from uuid import UUID

from fastapi import BackgroundTasks

from ..config import get_settings

log = logging.getLogger("campushub.matching")

DEFAULT_MODEL_DIR = Path(__file__).resolve().parents[2] / "models"
Mode = Literal["lambda", "inline", "off"]


def model_dir() -> str:
    return get_settings().match_model_dir or str(DEFAULT_MODEL_DIR)


def match_mode() -> Mode:
    s = get_settings()
    if s.match_mode != "auto":
        return s.match_mode
    if s.match_function:
        return "lambda"
    if importlib.util.find_spec("onnxruntime") is not None:
        from .models import models_present
        if models_present(model_dir()):
            return "inline"
    return "off"


def strength(score: float | None) -> Literal["strong", "possible"] | None:
    if score is None:
        return None
    return "strong" if score >= get_settings().match_strong else "possible"


def get_nsfw_classifier():
    """The obscene-photo model, or None where it isn't installed."""
    from .nsfw import nsfw_classifier, nsfw_model_present
    return nsfw_classifier(model_dir()) if nsfw_model_present(model_dir()) else None


def get_embedder():
    from .models import onnx_embedder
    return onnx_embedder(model_dir())


@lru_cache
def _lambda_client():
    import boto3
    return boto3.client("lambda")


async def _invoke_matcher(kind: str, report_id: UUID) -> None:
    payload = json.dumps({"kind": kind, "report_id": str(report_id)}).encode()
    try:
        await asyncio.to_thread(_lambda_client().invoke, FunctionName=get_settings().match_function,
                                InvocationType="Event", Payload=payload)
    except Exception:  # noqa: BLE001 - the report stays pending until the next backfill
        log.exception("Could not start matching for %s report %s", kind, report_id)


async def _run_inline(kind: str, report_id: UUID) -> None:
    from .engine import run_one
    try:
        await run_one(kind, report_id, get_embedder())
    except Exception:  # noqa: BLE001 - never break the request; the backfill retries it
        log.exception("Matching failed for %s report %s", kind, report_id)


async def _invoke_photo_screen(kind: str, item_id: UUID) -> None:
    payload = json.dumps({"screen": kind, "id": str(item_id)}).encode()
    try:
        await asyncio.to_thread(_lambda_client().invoke, FunctionName=get_settings().match_function,
                                InvocationType="Event", Payload=payload)
    except Exception:  # noqa: BLE001 - the photos just go unchecked; a moderator report still works
        log.exception("Could not start photo screening for %s %s", kind, item_id)


async def _photo_screen_inline(kind: str, item_id: UUID) -> None:
    classifier = get_nsfw_classifier()
    if classifier is None:
        return
    from .photo_screen import run_photo_screen
    try:
        await run_photo_screen(kind, item_id, classifier)
    except Exception:  # noqa: BLE001
        log.exception("Photo screening failed for %s %s", kind, item_id)


def request_photo_screen(background: BackgroundTasks, kind: str, item_id: UUID) -> None:
    """Check a post's photos for obscene images after the response (future plan §1.6).
    kind: listing, lost_report or found_report. Same modes as matching."""
    if not get_settings().auto_flag:
        return
    mode = match_mode()
    if mode == "lambda":
        background.add_task(_invoke_photo_screen, kind, item_id)
    elif mode == "inline":
        background.add_task(_photo_screen_inline, kind, item_id)


def request_match(background: BackgroundTasks, kind: str, report_id: UUID) -> None:
    mode = match_mode()
    if mode == "lambda":
        background.add_task(_invoke_matcher, kind, report_id)
    elif mode == "inline":
        background.add_task(_run_inline, kind, report_id)
