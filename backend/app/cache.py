"""Cache-aside layer backed by ElastiCache Redis, for the read-heavy list/browse endpoints that
queued up behind the DB connection pool under load testing (Locust at ~200 concurrent users).

One client per process, same shape as app/db.py's pool. If redis_host isn't set (local dev, or any
deployment without ElastiCache) every call below is a no-op that just runs the query -- caching is
strictly an optimization, never a correctness dependency, and a Redis outage must never take the
API down with it.

Cache keys must include whatever makes a response different for different callers (see each call
site): get_or_set() itself does no per-user scoping, so a key shared across two different viewers
would leak one viewer's view to another.
"""
import asyncio
import json
import logging
from collections.abc import Awaitable, Callable
from typing import Any

from fastapi.encoders import jsonable_encoder

from .config import get_settings

log = logging.getLogger("campushub.cache")

_client: Any | None = None
_client_loop: asyncio.AbstractEventLoop | None = None
_lock: asyncio.Lock | None = None
_lock_loop: asyncio.AbstractEventLoop | None = None
_warned_unavailable = False
_auth_token: str | None = None


def _secret_auth_token(secret_arn: str) -> str:
    """The Redis AUTH token from its Secrets Manager secret (fetched once per container, like
    app/db.py's DB credentials). The secret holds the raw token string, not JSON."""
    global _auth_token
    if _auth_token is None:
        import os

        import boto3
        region = os.environ.get("AWS_REGION") or get_settings().cognito_region
        _auth_token = (boto3.client("secretsmanager", region_name=region)
                       .get_secret_value(SecretId=secret_arn)["SecretString"])
    return _auth_token


async def _get_client() -> Any | None:
    """The Redis client, or None if caching is unconfigured (app/config.py's redis_host unset)."""
    global _client, _client_loop, _lock, _lock_loop
    s = get_settings()
    if not s.redis_host:
        return None
    loop = asyncio.get_running_loop()
    if _client is not None and _client_loop is loop:
        return _client
    if _lock is None or _lock_loop is not loop:
        _lock, _lock_loop = asyncio.Lock(), loop
    async with _lock:
        if _client is None or _client_loop is not loop:
            import redis.asyncio as redis
            auth_token = s.redis_auth_token
            if not auth_token and s.redis_auth_secret_arn:
                auth_token = await asyncio.to_thread(_secret_auth_token, s.redis_auth_secret_arn)
            _client = redis.Redis(
                host=s.redis_host,
                port=s.redis_port,
                password=auth_token or None,
                ssl=s.redis_tls,
                socket_connect_timeout=s.redis_connect_timeout_seconds,
                socket_timeout=s.redis_connect_timeout_seconds,
                decode_responses=True,
            )
            _client_loop = loop
    return _client


async def close() -> None:
    global _client, _client_loop
    if _client is not None:
        await _client.aclose()
    _client, _client_loop = None, None


async def get_or_set(key: str, ttl_seconds: int | None, fetch: Callable[[], Awaitable[Any]]) -> Any:
    """Returns the cached JSON value for `key`, or calls `fetch()`, caches its result (any shape
    fastapi.encoders.jsonable_encoder can handle -- Pydantic models, dicts of them, Decimal, UUID,
    datetime, ...) for `ttl_seconds` (app/config.py's redis_default_ttl_seconds if None), and
    returns that. On a cache hit the return value is plain dicts/lists/primitives, not the original
    model types -- fine here, since every call site's return value is re-validated by FastAPI's own
    response_model on the way out regardless of which shape it started as.

    Any Redis error (unreachable, timeout, auth failure) is logged once and treated as a cache
    miss: `fetch()` still runs and its result is still returned, just not cached.
    """
    global _warned_unavailable
    s = get_settings()
    client = None
    try:
        client = await _get_client()
        if client is not None:
            # The module's version is part of the key, so a write (invalidate()) retires every entry at once.
            version = await client.get(_version_key(_namespace(key))) or "0"
            key = f"{key}|v{version}"
            cached = await client.get(key)
            if cached is not None:
                return json.loads(cached)
    except Exception:  # noqa: BLE001
        if not _warned_unavailable:
            _warned_unavailable = True
            log.warning("Redis unavailable; serving uncached until it recovers", exc_info=True)
        client = None

    result = await fetch()

    if client is not None:
        try:
            payload = json.dumps(jsonable_encoder(result))
            await client.set(key, payload, ex=ttl_seconds or s.redis_default_ttl_seconds)
        except Exception:  # noqa: BLE001
            pass  # the response is already correct; just couldn't warm the cache for next time

    return result


def viewer_scope(viewer_id: Any) -> str:
    """The per-viewer part of a cache key: one shared entry for every guest, a separate one per
    signed-in user (their response may include things like "is_bookmarked" or "can_edit")."""
    return f"u:{viewer_id}" if viewer_id is not None else "guest"


def build_key(prefix: str, viewer_id: Any, *parts: Any) -> str:
    """A cache key covering `prefix`, the viewer (see viewer_scope) and every filter/query
    parameter in `parts` -- include everything the response depends on, or two different requests
    that should get different answers will share a cache entry."""
    return f"cache:{prefix}:{viewer_scope(viewer_id)}:" + json.dumps(parts, default=str)


# ---------------------------------------------------------------- invalidation
# Every key belongs to a module ("cache:<module>:..." from build_key, e.g. events, academics). A write in
# that module bumps the module's version number, and get_or_set puts the version in the key it reads, so
# the next read after a change misses and fetches fresh data: a change shows at once, not after the TTL.
# Old entries just expire. A write elsewhere (chat, notifications) leaves the caches alone.
NAMESPACES = ("buy-sell", "lost-found", "events", "academics", "mess")


def _namespace(key: str) -> str:
    return key.split(":", 2)[1] if key.startswith("cache:") else ""


def _version_key(namespace: str) -> str:
    return f"cachever:{namespace}"


async def invalidate(*namespaces: str) -> None:
    """Retire the cached reads of these modules (all of them if none is named). Best effort."""
    try:
        client = await _get_client()
        if client is None:
            return
        for ns in namespaces or NAMESPACES:
            await client.incr(_version_key(ns))
    except Exception:  # noqa: BLE001 - the TTL still bounds how stale a read can be
        log.warning("Couldn't invalidate the cache for %s", namespaces or "every module", exc_info=True)


# Which modules a write to a path can change. Moderation and account changes touch every module
# (a removed post, a deactivated seller); paths not listed (chat, notifications, uploads) touch none.
_WRITE_PATHS = (
    (("/listings", "/wanted", "/buy-sell/"), ("buy-sell",)),
    (("/lost-reports", "/found-reports", "/lost-found/"), ("lost-found",)),
    (("/events", "/event-tags", "/event-updates", "/me/followed-tags", "/me/bookmarks"), ("events",)),
    (("/departments", "/courses", "/materials", "/feedback", "/forums", "/threads", "/comments"), ("academics",)),
    (("/messes", "/mess-menus"), ("mess",)),
    (("/reports", "/seller-strikes", "/users", "/me/deactivate", "/me/reactivate", "/moderators",
      "/me/seller-unblock-request", "/seller-unblock-requests"), NAMESPACES),
)


def namespaces_for_write(path: str) -> tuple[str, ...]:
    """The modules whose cached reads a successful write to `path` (without the API prefix) may change."""
    hit: list[str] = []
    for prefixes, namespaces in _WRITE_PATHS:
        if any(path == p or path.startswith(p if p.endswith("/") else p + "/") or path.startswith(p + "?")
               for p in prefixes):
            hit += [ns for ns in namespaces if ns not in hit]
    return tuple(hit)
