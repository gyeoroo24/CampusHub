"""A change shows on the next read: cached reads are retired on writes, and signed-in reads aren't
edge-cached (the 30 s - 1 min lag on course materials and event bookmarks/follows)."""
import pytest

from app import cache

from .conftest import API, ASHA, category


class FakeRedis:
    def __init__(self):
        self.data: dict[str, str] = {}

    async def get(self, key):
        return self.data.get(key)

    async def set(self, key, value, ex=None):
        self.data[key] = value

    async def incr(self, key):
        self.data[key] = str(int(self.data.get(key, "0")) + 1)


@pytest.fixture
def redis(monkeypatch):
    fake = FakeRedis()

    async def client():
        return fake
    monkeypatch.setattr(cache, "_get_client", client)
    return fake


def test_a_write_retires_the_module_cache(client, redis):
    calls = []

    async def fetch():
        calls.append(1)
        return {"n": len(calls)}

    key = cache.build_key("events:list", None, "upcoming")
    first = client.portal.call(cache.get_or_set, key, 60, fetch)
    again = client.portal.call(cache.get_or_set, key, 60, fetch)
    assert first == again == {"n": 1}                     # cached
    client.portal.call(cache.invalidate, "academics")
    assert client.portal.call(cache.get_or_set, key, 60, fetch) == {"n": 1}   # another module: untouched
    client.portal.call(cache.invalidate, "events")
    assert client.portal.call(cache.get_or_set, key, 60, fetch) == {"n": 2}   # fresh after a change


def test_writes_map_to_the_modules_they_change():
    assert cache.namespaces_for_write("/materials/abc") == ("academics",)
    assert cache.namespaces_for_write("/courses/abc/materials") == ("academics",)
    assert cache.namespaces_for_write("/me/bookmarks/event/abc") == ("events",)
    assert cache.namespaces_for_write("/me/followed-tags/3") == ("events",)
    assert cache.namespaces_for_write("/buy-sell/categories/4") == ("buy-sell",)
    assert cache.namespaces_for_write("/reports/abc/resolve") == cache.NAMESPACES
    assert cache.namespaces_for_write("/chat/conversations/abc/messages") == ()
    assert cache.namespaces_for_write("/listingsx") == ()


def test_the_api_bumps_the_cache_on_writes(client, redis):
    category(client, ASHA, "buy-sell", "Books")
    assert redis.data.get("cachever:buy-sell") == "1"
    assert "cachever:events" not in redis.data


def test_signed_in_reads_are_not_edge_cached(client):
    assert client.get(f"{API}/events", headers=ASHA).headers["cache-control"] == "private, no-store"
    assert "cache-control" not in client.get(f"{API}/events").headers     # guests: CloudFront may cache
