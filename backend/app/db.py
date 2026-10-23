"""PostgreSQL connection pool (asyncpg).

One pool per process. In Lambda that means one per warm container, reused across
invocations; keep db_pool_max_size small (1-2) there and let RDS Proxy do the pooling.
"""
import asyncio
import json
from collections.abc import AsyncIterator

import asyncpg

from .config import get_settings

_pool: asyncpg.Pool | None = None
_pool_loop: asyncio.AbstractEventLoop | None = None
_lock: asyncio.Lock | None = None
_lock_loop: asyncio.AbstractEventLoop | None = None


async def _init_connection(conn: asyncpg.Connection) -> None:
    # Return JSONB columns (notifications.payload) as Python dicts.
    await conn.set_type_codec("jsonb", encoder=json.dumps, decoder=json.loads, schema="pg_catalog")


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
            s = get_settings()
            _pool = await asyncpg.create_pool(
                dsn=s.database_url,
                min_size=s.db_pool_min_size,
                max_size=s.db_pool_max_size,
                statement_cache_size=s.db_statement_cache_size,
                init=_init_connection,
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
    pool = await get_pool()
    async with pool.acquire() as conn:
        yield conn
