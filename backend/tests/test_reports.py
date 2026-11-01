import pytest

from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, as_user, category, grant, make_admin, sign_in, sql

BSMOD = as_user("bsmod@iisc.ac.in", "BSMod")
LFMOD = as_user("lfmod@iisc.ac.in", "LFMod")
COURSEMOD = as_user("coursemod@iisc.ac.in", "CourseMod")


@pytest.fixture
def setup(client):
    make_admin(client, ADMIN)
    for h in (BSMOD, LFMOD, COURSEMOD, ASHA, RAVI, MEERA, KIRAN):
        sign_in(client, h)
    grant(client, ADMIN, "bsmod@iisc.ac.in", "buy_sell")
    grant(client, ADMIN, "lfmod@iisc.ac.in", "lost_found")
    dept = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CSA"}).json()
    c1 = client.post(f"{API}/departments/{dept['id']}/courses", headers=ADMIN, json={"code": "E0 243", "name": "A"}).json()
    c2 = client.post(f"{API}/departments/{dept['id']}/courses", headers=ADMIN, json={"code": "E0 271", "name": "B"}).json()
    grant(client, ADMIN, "coursemod@iisc.ac.in", "academic_help", "course", course_id=c1["id"])
    cat = category(client, ASHA, "buy-sell", "Misc")
    listing = client.post(f"{API}/listings", headers=ASHA,
                          json={"title": "Vape pens", "price": "500", "category_id": cat}).json()
    threads = []
    for course in (c1, c2):
        forum = client.get(f"{API}/courses/{course['id']}/forum").json()
        threads.append(client.post(f"{API}/forums/{forum['id']}/threads", headers=ASHA,
                                   json={"title": "spam", "content": "buy followers"}).json())
    return {"listing": listing, "thread_c1": threads[0], "thread_c2": threads[1]}


def _report(client, who, target_type, target_id, reason="not allowed"):
    return client.post(f"{API}/reports", headers=who,
                       json={"target_type": target_type, "target_id": target_id, "reason": reason})


def test_one_open_report_per_person(client, setup):
    assert _report(client, RAVI, "listing", setup["listing"]["id"]).status_code == 201
    assert _report(client, RAVI, "listing", setup["listing"]["id"]).status_code == 409
    assert _report(client, MEERA, "listing", setup["listing"]["id"]).status_code == 201
    assert _report(client, RAVI, "listing", "00000000-0000-0000-0000-000000000000").status_code == 404
    mine = client.get(f"{API}/me/reports", headers=RAVI).json()["items"]
    assert len(mine) == 1 and mine[0]["module"] == "buy_sell" and mine[0]["reporter"] is None


def test_queues_are_scoped(client, setup):
    _report(client, RAVI, "listing", setup["listing"]["id"])
    _report(client, RAVI, "thread", setup["thread_c1"]["id"])
    _report(client, RAVI, "thread", setup["thread_c2"]["id"])
    queue = lambda h: {(r["target_type"], r["target_id"]) for r in  # noqa: E731
                       client.get(f"{API}/reports", headers=h).json()["items"]}
    assert queue(BSMOD) == {("listing", setup["listing"]["id"])}
    assert queue(LFMOD) == set()
    assert queue(COURSEMOD) == {("thread", setup["thread_c1"]["id"])}
    assert len(queue(ADMIN)) == 3
    assert client.get(f"{API}/reports", headers=KIRAN).status_code == 403


def test_resolve_and_remove_content(client, setup):
    listing_id = setup["listing"]["id"]
    first = _report(client, RAVI, "listing", listing_id).json()
    _report(client, MEERA, "listing", listing_id)
    assert client.post(f"{API}/reports/{first['id']}/resolve", headers=COURSEMOD,
                       json={"action": "actioned"}).status_code == 403
    r = client.post(f"{API}/reports/{first['id']}/resolve", headers=BSMOD,
                    json={"action": "actioned", "remove_content": True, "note": "Prohibited item"})
    assert r.json() == {"reports_resolved": 2, "content_removed": True}
    assert client.get(f"{API}/listings/{listing_id}").status_code == 404
    assert client.post(f"{API}/reports/{first['id']}/resolve", headers=BSMOD,
                       json={"action": "dismissed"}).status_code == 409
    statuses = sql("SELECT status::text AS s FROM reports WHERE listing_id = $1::uuid", listing_id)
    assert {r["s"] for r in statuses} == {"actioned"}


def test_dismiss_keeps_content(client, setup):
    rep = _report(client, RAVI, "thread", setup["thread_c1"]["id"]).json()
    r = client.post(f"{API}/reports/{rep['id']}/resolve", headers=COURSEMOD, json={"action": "dismissed"})
    assert r.json() == {"reports_resolved": 1, "content_removed": False}
    assert client.get(f"{API}/threads/{setup['thread_c1']['id']}").status_code == 200
