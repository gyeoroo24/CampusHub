"""Backend changes made for the 25 Oct 2026 frontend review: one review per person per course,
anonymous feedback, stepping down as moderator, admin lookup by email, and listing sort."""
from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, category, grant, make_admin, sign_in


def _course(client):
    make_admin(client, ADMIN)
    dept = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CDS"}).json()
    course = client.post(f"{API}/departments/{dept['id']}/courses", headers=ADMIN,
                         json={"code": "DS 252", "name": "Cloud Computing"}).json()
    return dept, course


def test_one_review_per_person_per_course(client):
    _, course = _course(client)
    url = f"{API}/courses/{course['id']}/feedback"
    first = client.post(url, headers=ASHA, json={"content": "Great course."})
    assert first.status_code == 201
    again = client.post(url, headers=ASHA, json={"content": "Great course!!!"})
    assert again.status_code == 409 and "already reviewed" in again.json()["detail"]
    assert client.get(f"{url}/mine", headers=ASHA).json()["id"] == first.json()["id"]
    assert client.get(f"{url}/mine", headers=RAVI).status_code == 404
    # After deleting it, the author may post again.
    assert client.delete(f"{API}/feedback/{first.json()['id']}", headers=ASHA).status_code == 204
    assert client.post(url, headers=ASHA, json={"content": "Second thoughts."}).status_code == 201


def test_names_hidden_for_guests_and_anonymous_feedback(client):
    _, course = _course(client)
    url = f"{API}/courses/{course['id']}/feedback"
    client.post(url, headers=ASHA, json={"content": "Named review."})
    client.post(url, headers=RAVI, json={"content": "Anonymous review.", "is_anonymous": True})

    def authors(headers=None):
        items = client.get(url, headers=headers).json()["items"]
        return {i["content"]: (i["author"]["name"] if i["author"] else None, i["is_mine"]) for i in items}

    assert authors() == {"Named review.": (None, False), "Anonymous review.": (None, False)}       # guest
    assert authors(MEERA) == {"Named review.": ("Asha", False), "Anonymous review.": (None, False)}
    assert authors(RAVI)["Anonymous review."] == ("Ravi", True)                                   # the author

    mine = client.get(f"{url}/mine", headers=ASHA).json()
    r = client.patch(f"{API}/feedback/{mine['id']}", headers=ASHA, json={"is_anonymous": True})
    assert r.json()["is_anonymous"] is True
    assert authors(MEERA)["Named review."] == (None, False)
    # A department moderator may edit the text but not reveal or hide the author.
    r = client.patch(f"{API}/feedback/{mine['id']}", headers=ADMIN, json={"is_anonymous": False})
    assert r.status_code == 403


def test_moderator_can_step_down(client):
    make_admin(client, ADMIN)
    sign_in(client, KIRAN)
    g = grant(client, ADMIN, "kiran@iisc.ac.in", "buy_sell").json()
    assert client.delete(f"{API}/moderators/{g['id']}", headers=MEERA).status_code == 403
    assert client.delete(f"{API}/moderators/{g['id']}", headers=KIRAN).status_code == 204
    assert client.get(f"{API}/me", headers=KIRAN).json()["moderator_grants"] == []


def test_admin_looks_up_accounts_by_email(client):
    make_admin(client, ADMIN)
    asha_id = sign_in(client, ASHA)
    r = client.get(f"{API}/users/lookup", params={"email": "ASHA@iisc.ac.in"}, headers=ADMIN)
    assert r.status_code == 200 and r.json()["id"] == asha_id and r.json()["is_active"] is True
    assert client.get(f"{API}/users/lookup", params={"email": "nobody@iisc.ac.in"}, headers=ADMIN).status_code == 404
    assert client.get(f"{API}/users/lookup", params={"email": "asha@iisc.ac.in"}, headers=RAVI).status_code == 403


def test_listings_sort_by_price(client):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    for title, price in (("Mid", "2000"), ("Cheap", "500"), ("Dear", "9000")):
        client.post(f"{API}/listings", headers=ASHA, json={"title": title, "price": price, "category_id": cycles})

    def titles(sort):
        return [i["title"] for i in client.get(f"{API}/listings", params={"sort": sort}).json()["items"]]

    assert titles("price_asc") == ["Cheap", "Mid", "Dear"]
    assert titles("price_desc") == ["Dear", "Mid", "Cheap"]
    assert titles("newest") == ["Dear", "Cheap", "Mid"]
    assert client.get(f"{API}/listings", params={"sort": "random"}).status_code == 422


def test_report_lists_filter_by_date_and_sort(client):
    from datetime import datetime, timedelta, timezone
    bottles = category(client, ASHA, "lost-found", "Water bottle")
    now = datetime.now(timezone.utc)
    for days, text in ((10, "old bottle"), (2, "recent bottle")):
        r = client.post(f"{API}/lost-reports", headers=ASHA, json={
            "description": text, "category_id": bottles, "occurred_at": (now - timedelta(days=days)).isoformat()})
        assert r.status_code == 201
    since = (now - timedelta(days=3)).isoformat()
    recent = client.get(f"{API}/lost-reports", params={"from_date": since}).json()["items"]
    assert [i["description"] for i in recent] == ["recent bottle"]
    older = client.get(f"{API}/lost-reports", params={"to_date": since}).json()["items"]
    assert [i["description"] for i in older] == ["old bottle"]
    assert [i["description"] for i in client.get(f"{API}/lost-reports", params={"sort": "oldest"}).json()["items"]] \
        == ["old bottle", "recent bottle"]


def test_reports_queue_all_statuses(client):
    make_admin(client, ADMIN)
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    a = client.post(f"{API}/listings", headers=ASHA, json={"title": "A", "price": "1", "category_id": cycles}).json()
    b = client.post(f"{API}/listings", headers=ASHA, json={"title": "B", "price": "1", "category_id": cycles}).json()
    for listing in (a, b):
        client.post(f"{API}/reports", headers=RAVI, json={"target_type": "listing", "target_id": listing["id"],
                                                          "reason": "spam"})
    first = client.get(f"{API}/reports", headers=ADMIN).json()["items"][0]
    client.post(f"{API}/reports/{first['id']}/resolve", headers=ADMIN, json={"action": "dismissed"})
    assert len(client.get(f"{API}/reports", headers=ADMIN).json()["items"]) == 1          # default: open
    assert len(client.get(f"{API}/reports", params={"status": "all"}, headers=ADMIN).json()["items"]) == 2
