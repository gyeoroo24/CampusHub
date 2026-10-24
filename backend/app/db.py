"""PostgreSQL connection pool (asyncpg).

One pool per process. In Lambda that means one per warm container, reused across
invocations; keep db_pool_max_size small (the default there is 2) and let RDS Proxy do the pooling.
"""
import asyncio
import json
import logging
import os
import time
from collections.abc import AsyncIterator

import asyncpg

from .config import get_settings

log = logging.getLogger("campushub.db")

_pool: asyncpg.Pool | None = None
_pool_loop: asyncio.AbstractEventLoop | None = None
_lock: asyncio.Lock | None = None
_lock_loop: asyncio.AbstractEventLoop | None = None
_last_used = 0.0
_credentials: dict | None = None


async def _init_connection(conn: asyncpg.Connection) -> None:
    # Return JSONB columns (notifications.payload) as Python dicts.
    await conn.set_type_codec("jsonb", encoder=json.dumps, decoder=json.loads, schema="pg_catalog")


def _secret_credentials(secret_arn: str) -> dict:
    """User and password from a Secrets Manager secret (fetched once per container)."""
    global _credentials
    if _credentials is None:
        import boto3
        region = os.environ.get("AWS_REGION") or get_settings().cognito_region
        secret = json.loads(boto3.client("secretsmanager", region_name=region)
                            .get_secret_value(SecretId=secret_arn)["SecretString"])
        _credentials = {"user": secret["username"], "password": secret["password"]}
    return _credentials


async def get_pool() -> asyncpg.Pool:
    """Create the pool on first use. Recreate it if the event loop changed (can happen in Lambda)."""
    global _pool, _pool_loop, _lock, _lock_loop
    loop = asyncio.get_running_loop()
    if _pool is not None and _pool_loop is loop:
        return _pool
    if _lock is None or _lock_loop is not loop:
        _lock, _lock_loop = asyncio.Lock(), loop
    async with _lock:
        if _pool is None or _pool_loop is not loop:
            if _pool is not None:
                # Its connections belong to the old loop and can't be closed gracefully from here.
                try:
                    _pool.terminate()
                except Exception:  # noqa: BLE001
                    log.warning("Could not terminate the previous connection pool", exc_info=True)
            s = get_settings()
            credentials = (await asyncio.to_thread(_secret_credentials, s.database_secret_arn)
                           if s.database_secret_arn else {})
            _pool = await asyncpg.create_pool(
                dsn=s.database_url,
                min_size=s.db_pool_min_size,
                max_size=s.db_pool_max_size,
                statement_cache_size=s.db_statement_cache_size,
                init=_init_connection,
                **credentials,
            )
            _pool_loop = loop
    return _pool


async def close_pool() -> None:
    global _pool, _pool_loop
    if _pool is not None:
        await _pool.close()
    _pool, _pool_loop = None, None


async def get_conn() -> AsyncIterator[asyncpg.Connection]:
    """FastAPI dependency: one connection per request, returned to the pool afterwards."""
    global _last_used
    pool = await get_pool()
    # Wall-clock time, because a frozen Lambda container's monotonic clock doesn't advance.
    now = time.time()
    if _last_used and now - _last_used > get_settings().db_idle_reconnect_seconds:
        # After a long freeze the proxy may have dropped our idle connections; open fresh ones.
        await pool.expire_connections()
    _last_used = now
    async with pool.acquire() as conn:
        yield conn
