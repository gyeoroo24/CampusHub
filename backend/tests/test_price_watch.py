"""Price watch and the Negotiable badge (future plan §2.3)."""
from .conftest import API, ASHA, KIRAN, RAVI, category


def _alerts(client, who):
    return [n["payload"] for n in client.get(f"{API}/me/notifications", headers=who).json()["items"]
            if n["type"] == "listing_watch"]


def _listing(client, price="4000"):
    cat = category(client, ASHA, "buy-sell", "Cycles")
    r = client.post(f"{API}/listings", headers=ASHA, json={"title": "Hero Sprint", "price": price, "category_id": cat})
    return r.json()


def test_watchers_hear_about_price_drops_and_negotiable(client):
    listing = _listing(client)
    url = f"{API}/listings/{listing['id']}"
    assert listing["negotiable"] is False
    assert client.put(f"{url}/watch", headers=ASHA).status_code == 422           # not your own
    for who in (RAVI, KIRAN):
        assert client.put(f"{url}/watch", headers=who).status_code == 204
    assert client.put(f"{url}/watch", headers=RAVI).status_code == 204           # idempotent
    assert client.get(url, headers=RAVI).json()["watching"] is True

    client.patch(url, headers=ASHA, json={"price": "3200"})
    [drop] = _alerts(client, RAVI)
    assert drop["message"] == 'Price drop on "Hero Sprint": ₹4,000 → ₹3,200' and drop["listing_id"] == listing["id"]

    assert client.delete(f"{url}/watch", headers=KIRAN).status_code == 204
    r = client.patch(url, headers=ASHA, json={"negotiable": True})
    assert r.json()["negotiable"] is True
    assert _alerts(client, RAVI)[0]["message"] == '"Hero Sprint" is now marked negotiable (₹3,200)'
    assert len(_alerts(client, KIRAN)) == 1                                       # stopped watching
    assert _alerts(client, ASHA) == []                                            # never the seller

    # Nothing to say: same price, or a description edit.
    client.patch(url, headers=ASHA, json={"price": "3200", "description": "Good brakes"})
    assert len(_alerts(client, RAVI)) == 2

    client.patch(url, headers=ASHA, json={"price": "3500"})
    assert _alerts(client, RAVI)[0]["message"].startswith('Price change on "Hero Sprint": ₹3,200 → ₹3,500')


def test_sold_listings_dont_alert_and_watch_list(client):
    listing = _listing(client)
    url = f"{API}/listings/{listing['id']}"
    client.put(f"{url}/watch", headers=RAVI)
    mine = client.get(f"{API}/me/watched-listings", headers=RAVI).json()["items"]
    assert [m["id"] for m in mine] == [listing["id"]]
    client.patch(f"{url}/status", headers=ASHA, json={"status": "sold"})
    client.patch(url, headers=ASHA, json={"price": "100"})
    assert _alerts(client, RAVI) == []


def test_negotiable_on_create(client):
    cat = category(client, ASHA, "buy-sell", "Books")
    r = client.post(f"{API}/listings", headers=ASHA, json={
        "title": "CLRS", "price": "500", "category_id": cat, "negotiable": True})
    assert r.json()["negotiable"] is True
    assert client.get(f"{API}/listings").json()["items"][0]["negotiable"] is True
