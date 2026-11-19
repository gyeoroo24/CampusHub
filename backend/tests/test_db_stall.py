"""A stalled database makes requests fail fast with a 503, not hang (issue #11).

The app's pool is pointed at a small TCP proxy in front of the test database. Pausing the proxy
holds every byte in both directions, which looks to the app exactly like `docker pause` on the
Postgres container, or an RDS Multi-AZ failover: connections stay open but nothing answers.
Timeouts are shortened for the tests, so every case here finishes in a few seconds.
"""
import asyncio
import contextlib
import threading
import time
from urllib.parse import urlsplit

import httpx
import pytest

from app import db
from app.config import get_settings

from .conftest import API, ASHA, DB_URL

COMMAND_TIMEOUT = 1.0
HEALTH_TIMEOUT = 0.5
# How long a stalled request may take: its query's timeout plus generous slack for a busy machine.
# Before the fix these hung until the client gave up (a write in a transaction hung forever).
FAST = COMMAND_TIMEOUT + 2.0


class StallProxy:
    """TCP proxy to the test database, on its own thread and event loop. pause() freezes it."""

    def __init__(self, upstream_host: str, upstream_port: int):
        self.upstream = (upstream_host, upstream_port)
        self.paused = threading.Event()
        self.loop = asyncio.new_event_loop()
        self.port: int | None = None
        self._writers: set[asyncio.StreamWriter] = set()
        self._ready = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def __enter__(self):
        self._thread.start()
        self._ready.wait(5)
        return self

    def __exit__(self, *exc):
        self.paused.clear()
        self.loop.call_soon_threadsafe(self._stop.set)
        self._thread.join(5)

    def pause(self):
        self.paused.set()

    def resume(self):
        self.paused.clear()

    async def _held(self):
        while self.paused.is_set():
            await asyncio.sleep(0.02)

    async def _pump(self, reader, writer):
        try:
            while data := await reader.read(65536):
                await self._held()
                writer.write(data)
                await writer.drain()
        except (ConnectionError, asyncio.CancelledError):
            pass
        finally:
            writer.close()

    async def _handle(self, client_reader, client_writer):
        self._writers.add(client_writer)
        await self._held()                 # a new connection isn't answered while paused either
        try:
            up_reader, up_writer = await asyncio.open_connection(*self.upstream)
        except OSError:
            client_writer.close()
            return
        self._writers.add(up_writer)
        await asyncio.gather(self._pump(client_reader, up_writer), self._pump(up_reader, client_writer))

    def _run(self):
        asyncio.set_event_loop(self.loop)

        async def main():
            self._stop = asyncio.Event()
            server = await asyncio.start_server(self._handle, "127.0.0.1", 0)
            self.port = server.sockets[0].getsockname()[1]
            self._ready.set()
            await self._stop.wait()
            server.close()
            # Close every socket, so anything the app still has waiting on one fails at once
            # instead of waiting for a TCP timeout (which made a failing run take most of an hour).
            for writer in self._writers:
                writer.transport.abort()
            tasks = asyncio.all_tasks() - {asyncio.current_task()}
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

        self.loop.run_until_complete(main())
        self.loop.close()


@pytest.fixture
def stalled_db(client, monkeypatch):
    """The app talks to the database through a pausable proxy, with short timeouts."""
    url = urlsplit(DB_URL)
    with StallProxy(url.hostname, url.port or 5432) as proxy:
        settings = get_settings()
        monkeypatch.setattr(settings, "database_url", url._replace(
            netloc=f"{url.username}:{url.password}@127.0.0.1:{proxy.port}").geturl())
        monkeypatch.setattr(settings, "db_command_timeout_seconds", COMMAND_TIMEOUT)
        monkeypatch.setattr(settings, "db_connect_timeout_seconds", COMMAND_TIMEOUT)
        monkeypatch.setattr(settings, "db_acquire_timeout_seconds", COMMAND_TIMEOUT)
        monkeypatch.setattr(settings, "db_cancel_timeout_seconds", 0.3)
        monkeypatch.setattr(settings, "health_db_timeout_seconds", HEALTH_TIMEOUT)
        client.portal.call(db.close_pool)          # the next request opens a pool through the proxy
        try:
            yield proxy
        finally:
            proxy.resume()
            # Later tests get a fresh pool to the real database. Terminate rather than close: if a
            # test failed because a request is still stuck, close() would wait for it forever.
            client.portal.call(_drop_pool)


async def _drop_pool():
    if db._pool is not None:
        db._pool.terminate()
    db._pool = db._pool_loop = None


async def _bounded(coro, limit: float):
    """Run coro, giving up after `limit` seconds. asyncio.wait, not wait_for: if the bug comes back,
    the test must fail, not hang the whole run waiting for the stuck request to be cancelled."""
    task = asyncio.ensure_future(coro)
    done, _ = await asyncio.wait({task}, timeout=limit)
    if not done:
        task.cancel()
        raise AssertionError(f"still hanging after {limit:.1f}s: the database stall wasn't cut short")
    return task.result()


def stalled_request(client, method: str, path: str, limit: float = FAST, **kwargs):
    """One request through the app while the database is stalled. Returns (response, seconds).

    Sent on the app's own loop (the TestClient's portal) rather than with client.get(): TestClient
    has no timeout, so a regression would block forever instead of failing.
    """
    async def send():
        transport = httpx.ASGITransport(app=client.app)   # client host 127.0.0.1: dev sign-in works
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as http:
            return await http.request(method, f"{API}{path}", **kwargs)

    started = time.monotonic()
    response = client.portal.call(_bounded, send(), limit)
    return response, time.monotonic() - started


def test_health_answers_fast_while_db_is_stalled(client, stalled_db):
    assert client.get(f"{API}/health").status_code == 200
    stalled_db.pause()
    r, _ = stalled_request(client, "GET", "/health", limit=HEALTH_TIMEOUT + 1.0)
    assert r.status_code == 503, r.text
    assert r.json()["status"] == "unavailable"
    stalled_db.resume()
    assert client.get(f"{API}/health").json() == {"status": "ok"}


def test_read_fails_fast_with_retryable_503_and_recovers(client, stalled_db):
    assert client.get(f"{API}/listings?limit=3").status_code == 200   # pool warm, connection open
    stalled_db.pause()
    r, _ = stalled_request(client, "GET", "/listings?limit=3")
    assert r.status_code == 503, r.text
    assert r.headers["retry-after"] == "5"
    stalled_db.resume()
    assert client.get(f"{API}/listings?limit=3").status_code == 200   # no restart needed


def test_write_fails_fast_and_is_not_applied(client, stalled_db):
    assert client.patch(f"{API}/me", headers=ASHA, json={"name": "Before"}).status_code == 200
    stalled_db.pause()
    r, _ = stalled_request(client, "PATCH", "/me", headers=ASHA, json={"name": "During"})
    assert r.status_code == 503, r.text
    stalled_db.resume()
    assert client.get(f"{API}/me", headers=ASHA).json()["name"] == "Before"
    assert client.patch(f"{API}/me", headers=ASHA, json={"name": "After"}).json()["name"] == "After"


def test_stall_inside_a_transaction_fails_fast(client, stalled_db):
    """The hard case: the database stops answering between two statements of a transaction.

    Stock asyncpg makes the transaction's ROLLBACK wait for the stalled server to answer the
    timed-out query, with no limit, so this used to hang forever. Runs the route's steps on the
    app's own loop, through get_conn, the way FastAPI does.
    """
    async def write_route():
        deps = db.get_conn()
        conn = await deps.__anext__()
        try:
            async with conn.transaction():
                await conn.fetchval("SELECT 1")
                stalled_db.pause()
                await conn.fetchval("SELECT count(*) FROM users")
        except Exception as exc:          # FastAPI hands the route's error to the dependency
            with contextlib.suppress(StopAsyncIteration):
                await deps.athrow(exc)
            raise AssertionError("get_conn swallowed the error")  # pragma: no cover

    with pytest.raises(db.DatabaseUnavailable):
        client.portal.call(_bounded, write_route(), FAST)

    stalled_db.resume()
    assert client.get(f"{API}/listings?limit=3").status_code == 200
