from datetime import datetime, timedelta, timezone

from .conftest import API, ASHA, KIRAN, MEERA, RAVI, category, upload


def _when(days_ago: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).isoformat()


def _file(client, headers, kind, cat, days_ago, description="Blue IISc ID card", **extra):
    r = client.post(f"{API}/{kind}-reports", headers=headers, json={
        "description": description, "category_id": cat, "occurred_at": _when(days_ago),
        "location": "Main library"} | extra)
    assert r.status_code == 201, r.text
    return r.json()


def test_categories_are_deduplicated(client):
    first = client.post(f"{API}/lost-found/categories", headers=ASHA, json={"name": "ID card"})
    again = client.post(f"{API}/lost-found/categories", headers=RAVI, json={"name": "  id   CARD "})
    assert first.status_code == 201 and again.status_code == 200
    assert first.json()["id"] == again.json()["id"]
    assert [c["name"] for c in client.get(f"{API}/lost-found/categories").json()] == ["ID card"]


def test_found_report_notifies_everyone_who_lost_that_item(client):
    """FR-9: Asha and Ravi both lost ID cards; Meera finds one."""
    id_card = category(client, ASHA, "lost-found", "ID card")
    bottle = category(client, ASHA, "lost-found", "Water bottle")
    _file(client, ASHA, "lost", id_card, 3)
    _file(client, RAVI, "lost", id_card, 1)
    _file(client, KIRAN, "lost", bottle, 1, description="Milton bottle")
    found = _file(client, MEERA, "found", id_card, 0.1)

    assert {m["reporter"]["name"] for m in found["possible_matches"]} == {"Asha", "Ravi"}
    for who in (ASHA, RAVI):
        items = client.get(f"{API}/me/notifications", headers=who).json()["items"]
        assert len(items) == 1 and items[0]["type"] == "lost_found_match"
        assert items[0]["payload"]["found_report_id"] == found["id"]
    for who in (MEERA, KIRAN):
        assert client.get(f"{API}/me/notifications", headers=who).json()["items"] == []


def test_lost_report_shows_items_already_found(client):
    id_card = category(client, ASHA, "lost-found", "ID card")
    found = _file(client, MEERA, "found", id_card, 1)
    lost = _file(client, ASHA, "lost", id_card, 2)
    assert [m["id"] for m in lost["possible_matches"]] == [found["id"]]


def test_reports_with_photos_and_status(client, s3):
    id_card = category(client, ASHA, "lost-found", "ID card")
    p1, p2 = upload(client, s3, ASHA, "lost_report_photo", b"1"), upload(client, s3, ASHA, "lost_report_photo", b"2")
    lost = _file(client, ASHA, "lost", id_card, 1, photo_keys=[p1, p2])
    assert len(lost["photos"]) == 2
    # a lost-report photo can't be reused for a found report
    r = client.post(f"{API}/found-reports", headers=ASHA, json={
        "description": "x", "category_id": id_card, "occurred_at": _when(0), "photo_keys": [p1]})
    assert r.status_code == 422
    url = f"{API}/lost-reports/{lost['id']}/status"
    assert client.patch(url, headers=RAVI, json={"status": "closed"}).status_code == 403
    assert client.patch(url, headers=ASHA, json={"status": "closed"}).json()["status"] == "closed"
    assert client.patch(url, headers=ASHA, json={"status": "matched"}).status_code == 422   # removed in rev 11


def test_future_time_rejected(client):
    id_card = category(client, ASHA, "lost-found", "ID card")
    r = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "description": "x", "category_id": id_card, "occurred_at": _when(-2)})
    assert r.status_code == 422


def test_lost_and_found_feeds_are_separate(client):
    """FR-7 / FR-8."""
    id_card = category(client, ASHA, "lost-found", "ID card")
    lost = _file(client, ASHA, "lost", id_card, 1)
    found = _file(client, MEERA, "found", id_card, 0.5)
    assert [i["id"] for i in client.get(f"{API}/lost-reports").json()["items"]] == [lost["id"]]
    assert [i["id"] for i in client.get(f"{API}/found-reports").json()["items"]] == [found["id"]]


def test_reports_have_titles_that_search_and_chat_use(client):
    """Rev 25: a report may have a short title. Search matches it; reports without one still work."""
    cat = category(client, ASHA, "lost-found", "Electronics")
    r = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "title": "Black JBL earbuds", "description": "In a small case, near the library",
        "category_id": cat, "occurred_at": "2026-10-01T10:00:00Z"})
    assert r.status_code == 201, r.text
    assert r.json()["title"] == "Black JBL earbuds"
    assert [i["title"] for i in client.get(f"{API}/lost-reports", params={"q": "jbl"}).json()["items"]] == ["Black JBL earbuds"]
    old = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "description": "Blue water bottle", "category_id": cat, "occurred_at": "2026-10-01T10:00:00Z"}).json()
    assert old["title"] is None
    edited = client.patch(f"{API}/lost-reports/{old['id']}", headers=ASHA, json={"title": "Milton bottle"}).json()
    assert edited["title"] == "Milton bottle"
    assert client.post(f"{API}/lost-reports", headers=ASHA, json={
        "title": "   ", "description": "x", "category_id": cat, "occurred_at": "2026-10-01T10:00:00Z"}).status_code == 422
