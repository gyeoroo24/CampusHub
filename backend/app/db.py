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


class DatabaseUnavailable(Exception):
    """The database stalled or dropped the connection mid-request. errors.py turns it into a 503."""


# Background cancel requests (see _FailFastConnection), kept referenced until they finish.
_cancel_tasks: set[asyncio.Task] = set()


class _FailFastConnection(asyncpg.Connection):
    """A connection that is closed as soon as one of its queries times out.

    Stock asyncpg cancels a timed-out query over a *new* connection to the server, and every later
    query on this connection (a transaction's ROLLBACK, the pool's reset on release) first waits,
    with no time limit, for the server to answer the cancelled query. If the server is stalled that
    never happens, so the request hangs despite command_timeout. Measured locally with a frozen
    database: a write inside a transaction hung indefinitely.

    Instead, close the connection right away (the pool opens a fresh one when needed): the caller
    gets its TimeoutError, and anything else on this connection fails at once instead of waiting.
    The server-side cancel is still sent, separately and with a short limit, so a merely slow query
    on a healthy database doesn't keep running there.

    Overrides asyncpg's private Connection._cancel_current_command (asyncpg is pinned in
    requirements.txt; re-check this if upgrading it).
    """

    def _cancel_current_command(self, waiter):
        proto = self._protocol
        task = self._loop.create_task(self._cancel_on_server(proto.backend_pid, proto.backend_secret))
        _cancel_tasks.add(task)
        task.add_done_callback(_cancel_tasks.discard)
        if not waiter.done():
            waiter.set_result(None)
        # Not synchronously: asyncpg's protocol still uses the transport right after this returns.
        # call_soon runs before the timed-out caller resumes, so its ROLLBACK sees a closed connection.
        self._loop.call_soon(self._close_now)

    def _close_now(self) -> None:
        if not self.is_closed():
            log.warning("A query timed out; closing its database connection")
            self.terminate()

    async def _cancel_on_server(self, backend_pid, backend_secret) -> None:
        from asyncpg import connect_utils
        try:
            await asyncio.wait_for(
                connect_utils._cancel(loop=self._loop, addr=self._addr, params=self._params,
                                      backend_pid=backend_pid, backend_secret=backend_secret),
                get_settings().db_cancel_timeout_seconds)
        except (Exception, asyncio.CancelledError):  # noqa: BLE001 - best effort; the server may be down
            log.info("Could not cancel a timed-out query on the server", exc_info=True)


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
                timeout=s.db_connect_timeout_seconds,
                command_timeout=s.db_command_timeout_seconds,
                connection_class=_FailFastConnection,
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
    async with pool.acquire(timeout=get_settings().db_acquire_timeout_seconds) as conn:
        try:
            yield conn
        except Exception as exc:
            # A query timed out (its connection is then closed, see _FailFastConnection) or the
            # connection broke. Either way the error the route ends with can be a TimeoutError, a
            # ConnectionDoesNotExistError, or an InterfaceError from a ROLLBACK on the closed
            # connection: report them all as one retryable "database unavailable".
            if isinstance(exc, (TimeoutError, ConnectionError)) or _is_closed(conn):
                raise DatabaseUnavailable() from exc
            raise


def _is_closed(conn: asyncpg.Connection) -> bool:
    try:
        return conn.is_closed()
    except asyncpg.exceptions.InterfaceError:
        # A terminated pool connection is detached from its proxy, and every call on it raises.
        return True


async def ping(timeout: float) -> None:
    """SELECT 1 that answers within `timeout` seconds, raising TimeoutError (or the DB error) if not.

    Creating the pool (in Lambda: fetching the database secret on a cold start) isn't counted, so a
    cold container's first health check isn't failed for being slow to start. Uses asyncio.wait
    rather than wait_for: wait_for also waits for the cancelled check to clean up (an in-progress
    connect to a stalled server isn't interrupted promptly), so it can overrun.
    """
    pool = await get_pool()

    async def _check() -> None:
        async with pool.acquire(timeout=timeout) as conn:
            await conn.fetchval("SELECT 1", timeout=timeout)

    task = asyncio.ensure_future(_check())
    done, _ = await asyncio.wait({task}, timeout=timeout)
    if not done:
        task.cancel()   # finishes cleaning up in the background
        task.add_done_callback(lambda t: t.cancelled() or t.exception())   # no "never retrieved" log
        raise TimeoutError(f"database did not answer within {timeout}s")
    task.result()
