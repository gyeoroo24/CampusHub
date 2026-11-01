"""Rev 6 features from "Taking it further": saved searches and alerts, Wanted posts, campus services,
and the course survival guide."""
from datetime import datetime, timedelta, timezone

from .conftest import as_user, ADMIN, API, ASHA, KIRAN, MEERA, RAVI, category, grant, make_admin, sign_in, sql


def _listing(client, headers, cat, **fields):
    body = {"title": "Hero cycle", "description": "Good condition", "price": "2500", "category_id": cat} | fields
    r = client.post(f"{API}/listings", headers=headers, json=body)
    assert r.status_code == 201, r.text
    return r.json()


def _alerts(client, headers, kind):
    items = client.get(f"{API}/me/notifications", headers=headers).json()["items"]
    return [n["payload"] for n in items if n["type"] == kind]


# ---------------------------------------------------------------- saved searches
def test_saved_search_alerts_once_per_matching_listing(client):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    books = category(client, ASHA, "buy-sell", "Books")
    r = client.post(f"{API}/me/saved-searches", headers=RAVI, json={
        "module": "buy_sell", "name": "Cycle under 3000", "q": "cycle", "category_id": cycles, "max_price": "3000"})
    assert r.status_code == 201, r.text
    search = r.json()
    assert search["new_count"] == 0 and search["category_name"] == "Cycles"

    match = _listing(client, ASHA, cycles, title="Hero cycle", price="2500")
    _listing(client, ASHA, cycles, title="Firefox cycle", price="9000")          # too expensive
    _listing(client, ASHA, books, title="Cycle repair manual", price="300")      # wrong category
    _listing(client, RAVI, cycles, title="My own cycle", price="1000")           # Ravi's own listing
    alerts = _alerts(client, RAVI, "saved_search_match")
    assert [a["listing_id"] for a in alerts] == [match["id"]]
    assert "Cycle under 3000" in alerts[0]["message"] and "₹2,500" in alerts[0]["message"]

    # Editing the matching listing doesn't alert again; a price drop into range does alert.
    client.patch(f"{API}/listings/{match['id']}", headers=ASHA, json={"price": "2400"})
    pricey = client.get(f"{API}/listings", params={"q": "Firefox"}).json()["items"][0]
    client.patch(f"{API}/listings/{pricey['id']}", headers=ASHA, json={"price": "2999"})
    assert [a["listing_id"] for a in _alerts(client, RAVI, "saved_search_match")] == [pricey["id"], match["id"]]

    listed = client.get(f"{API}/me/saved-searches", headers=RAVI).json()
    assert listed[0]["new_count"] == 2
    assert client.post(f"{API}/me/saved-searches/{search['id']}/seen", headers=RAVI).json()["new_count"] == 0


def test_saved_search_alerts_can_be_paused_and_are_private(client):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    search = client.post(f"{API}/me/saved-searches", headers=RAVI, json={
        "module": "buy_sell", "name": "Any cycle", "category_id": cycles, "alerts_enabled": False}).json()
    _listing(client, ASHA, cycles)
    assert _alerts(client, RAVI, "saved_search_match") == []
    assert client.get(f"{API}/me/saved-searches", headers=RAVI).json()[0]["new_count"] == 1   # badge still counts

    assert client.get(f"{API}/me/saved-searches", headers=MEERA).json() == []
    assert client.patch(f"{API}/me/saved-searches/{search['id']}", headers=MEERA, json={"name": "x"}).status_code == 404
    assert client.delete(f"{API}/me/saved-searches/{search['id']}", headers=MEERA).status_code == 404
    r = client.patch(f"{API}/me/saved-searches/{search['id']}", headers=RAVI, json={"alerts_enabled": True, "q": ""})
    assert r.json()["alerts_enabled"] is True and r.json()["q"] is None
    assert client.delete(f"{API}/me/saved-searches/{search['id']}", headers=RAVI).status_code == 204
    assert client.get(f"{API}/me/saved-searches", headers=RAVI).json() == []


def test_saved_search_validation(client):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    id_cards = category(client, ASHA, "lost-found", "ID card")
    bad = [
        {"module": "lost_found", "name": "x", "max_price": "10"},              # no prices in Lost & Found
        {"module": "buy_sell", "name": "x", "min_price": "10", "max_price": "5"},
        {"module": "buy_sell", "name": " ", "category_id": cycles},
        {"module": "events", "name": "x"},
        {"module": "buy_sell", "name": "hero cycle"},          # no keyword or filter: would match everything
        {"module": "buy_sell", "name": "hero cycle", "q": "  "},
    ]
    for body in bad:
        assert client.post(f"{API}/me/saved-searches", headers=RAVI, json=body).status_code == 422, body
    r = client.post(f"{API}/me/saved-searches", headers=RAVI,
                    json={"module": "lost_found", "name": "x", "category_id": cycles + id_cards + 100})
    assert r.status_code == 422   # no such Lost & Found category
    assert client.post(f"{API}/me/saved-searches", json={"module": "buy_sell", "name": "x"}).status_code == 401
    for i in range(20):
        assert client.post(f"{API}/me/saved-searches", headers=KIRAN,
                           json={"module": "buy_sell", "name": f"s{i}", "q": f"word{i}"}).status_code == 201
    assert client.post(f"{API}/me/saved-searches", headers=KIRAN,
                       json={"module": "buy_sell", "name": "one too many", "q": "x"}).status_code == 409
    mine = client.get(f"{API}/me/saved-searches", headers=KIRAN).json()
    mine = mine["items"] if isinstance(mine, dict) else mine
    r = client.patch(f"{API}/me/saved-searches/{mine[0]['id']}", headers=KIRAN, json={"q": None})
    assert r.status_code == 422   # clearing the only filter


def test_lost_found_saved_search_alerts_on_found_reports(client):
    id_cards = category(client, ASHA, "lost-found", "ID card")
    bottles = category(client, ASHA, "lost-found", "Water bottle")
    client.post(f"{API}/me/saved-searches", headers=RAVI, json={
        "module": "lost_found", "name": "My ID card", "category_id": id_cards, "q": "blue"})
    when = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()

    def found(cat, description):
        r = client.post(f"{API}/found-reports", headers=ASHA,
                        json={"description": description, "category_id": cat, "occurred_at": when})
        assert r.status_code == 201, r.text
        return r.json()

    found(id_cards, "Red lanyard ID card")                    # keyword doesn't match
    found(bottles, "Blue bottle")                              # wrong category
    hit = found(id_cards, "ID card in a BLUE lanyard (50% faded)")
    alerts = _alerts(client, RAVI, "saved_search_match")
    assert [a["found_report_id"] for a in alerts] == [hit["id"]]
    # A lost report doesn't trigger saved searches (they watch found items).
    client.post(f"{API}/lost-reports", headers=MEERA,
                json={"description": "Blue ID card", "category_id": id_cards, "occurred_at": when})
    assert len(_alerts(client, RAVI, "saved_search_match")) == 1


# ---------------------------------------------------------------- wanted posts
def test_wanted_post_shows_matches_and_alerts_on_new_listing(client):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    old = _listing(client, ASHA, cycles, title="Hero Sprint cycle", price="2800")
    _listing(client, ASHA, cycles, title="Btwin Rockrider", description="7 gears", price="6000")   # over budget
    r = client.post(f"{API}/wanted", headers=RAVI, json={
        "title": "Need a Hero cycle", "description": "For campus rides", "category_id": cycles, "max_price": "3000"})
    assert r.status_code == 201, r.text
    post = r.json()
    assert [m["id"] for m in post["possible_matches"]] == [old["id"]]
    assert post["author_contact"]["email"] == "ravi@iisc.ac.in"

    new = _listing(client, MEERA, cycles, title="Hero Jet cycle", price="1500")
    _listing(client, MEERA, cycles, title="Firefox", description="mountain bike", price="2000")   # no shared word
    alerts = _alerts(client, RAVI, "wanted_post_match")
    assert [(a["listing_id"], a["wanted_post_id"]) for a in alerts] == [(new["id"], post["id"])]
    assert [m["id"] for m in client.get(f"{API}/wanted/{post['id']}/matches").json()] == [new["id"], old["id"]]

    # Once fulfilled, no more alerts, and it leaves the default (open) feed.
    client.patch(f"{API}/wanted/{post['id']}/status", headers=RAVI, json={"status": "fulfilled"})
    _listing(client, MEERA, cycles, title="Another Hero cycle", price="1000")
    assert len(_alerts(client, RAVI, "wanted_post_match")) == 1
    assert client.get(f"{API}/wanted").json()["items"] == []
    assert len(client.get(f"{API}/wanted", params={"status": "fulfilled"}).json()["items"]) == 1


def test_wanted_post_browse_edit_and_permissions(client):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    books = category(client, ASHA, "buy-sell", "Books")
    a = client.post(f"{API}/wanted", headers=RAVI, json={"title": "CLRS book", "category_id": books}).json()
    client.post(f"{API}/wanted", headers=MEERA, json={"title": "Any cycle", "category_id": cycles})
    guest = client.get(f"{API}/wanted", params={"q": "clrs"}).json()["items"]
    assert [p["id"] for p in guest] == [a["id"]] and guest[0]["max_price"] is None
    assert client.get(f"{API}/wanted/{a['id']}").json()["author_contact"] is None

    assert client.patch(f"{API}/wanted/{a['id']}", headers=MEERA, json={"title": "x"}).status_code == 403
    r = client.patch(f"{API}/wanted/{a['id']}", headers=RAVI, json={"max_price": "500", "title": "CLRS 3rd ed"})
    assert r.json()["max_price"] == "500.00" and r.json()["title"] == "CLRS 3rd ed"
    assert client.patch(f"{API}/wanted/{a['id']}", headers=RAVI, json={"title": None}).status_code == 422
    assert client.post(f"{API}/wanted", headers=RAVI, json={"title": "x", "category_id": 999}).status_code == 422
    assert client.delete(f"{API}/wanted/{a['id']}", headers=MEERA).status_code == 403
    assert client.delete(f"{API}/wanted/{a['id']}", headers=RAVI).status_code == 204
    assert client.get(f"{API}/wanted/{a['id']}").status_code == 404


def test_wanted_post_can_be_reported_and_removed_by_moderator(client):
    make_admin(client, ADMIN)
    sign_in(client, KIRAN)
    assert grant(client, ADMIN, "kiran@iisc.ac.in", "buy_sell").status_code == 201
    books = category(client, ASHA, "buy-sell", "Books")
    post = client.post(f"{API}/wanted", headers=RAVI, json={"title": "Exam answers for sale?", "category_id": books}).json()
    r = client.post(f"{API}/reports", headers=MEERA,
                    json={"target_type": "wanted_post", "target_id": post["id"], "reason": "Cheating"})
    assert r.status_code == 201, r.text
    assert r.json()["module"] == "buy_sell"
    queue = client.get(f"{API}/reports", headers=KIRAN).json()["items"]
    assert [q["target_id"] for q in queue] == [post["id"]]
    r = client.post(f"{API}/reports/{queue[0]['id']}/resolve", headers=KIRAN,
                    json={"action": "actioned", "remove_content": True})
    assert r.json() == {"reports_resolved": 1, "content_removed": True}
    assert client.get(f"{API}/wanted/{post['id']}").status_code == 404


# ---------------------------------------------------------------- campus services
def test_campus_services_public_read_admin_write(client):
    make_admin(client, ADMIN)
    body = {"name": "Wellness Centre", "category": "wellbeing", "url": "https://wellness.iisc.ac.in/"}
    assert client.post(f"{API}/campus-services", headers=RAVI, json=body).status_code == 403
    wellness = client.post(f"{API}/campus-services", headers=ADMIN, json=body).json()
    health = client.post(f"{API}/campus-services", headers=ADMIN, json={
        "name": "Emergency", "category": "health", "phone": "080-2293-4444"}).json()
    hidden = client.post(f"{API}/campus-services", headers=ADMIN, json={
        "name": "Old portal", "category": "grievance", "url": "https://example.org", "is_active": False}).json()
    assert [s["name"] for s in client.get(f"{API}/campus-services").json()] == ["Emergency", "Wellness Centre"]
    assert len(client.get(f"{API}/campus-services", params={"include_inactive": True}).json()) == 2   # guests
    assert len(client.get(f"{API}/campus-services", headers=ADMIN, params={"include_inactive": True}).json()) == 3

    for bad in ({"name": "x", "category": "health"},                                  # no url or phone
                {"name": "x", "category": "health", "url": "javascript:alert(1)"},
                {"name": "x", "category": "food", "url": "https://x.org"}):
        assert client.post(f"{API}/campus-services", headers=ADMIN, json=bad).status_code == 422, bad
    assert client.patch(f"{API}/campus-services/{health['id']}", headers=ADMIN,
                        json={"phone": None}).status_code == 422                     # would leave no contact
    r = client.patch(f"{API}/campus-services/{wellness['id']}", headers=ADMIN, json={"sort_order": 5})
    assert r.json()["sort_order"] == 5
    assert client.delete(f"{API}/campus-services/{hidden['id']}", headers=RAVI).status_code == 403
    assert client.delete(f"{API}/campus-services/{hidden['id']}", headers=ADMIN).status_code == 204


# ---------------------------------------------------------------- survival guide
def _course(client):
    make_admin(client, ADMIN)
    dept = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CDS"}).json()
    return client.post(f"{API}/departments/{dept['id']}/courses", headers=ADMIN,
                       json={"code": "DS 252", "name": "Cloud Computing"}).json()


def _feedback(client, course_id, headers, content, written_at):
    r = client.post(f"{API}/courses/{course_id}/feedback", headers=headers, json={"content": content})
    assert r.status_code == 201, r.text
    sql("UPDATE course_feedback SET created_at = $2::timestamptz WHERE id = $1::uuid", r.json()["id"], datetime.fromisoformat(written_at))


def test_survival_guide_groups_by_semester_and_shows_trend(client):
    course = _course(client)
    terms = [("2023-11-20T10:00:00+05:30", "The pace was brutal and grading was opaque. Start the project early."),
             ("2024-12-01T10:00:00+05:30", "Content is good but the workload is heavy. Start the project early."),
             ("2025-11-25T10:00:00+05:30", "One of the best courses, the instructor explains really clearly.")]
    for t, (when, text) in enumerate(terms):
        for n in range(3):   # one review per person per course, so each semester has its own students
            _feedback(client, course["id"], as_user(f"student{t}{n}@iisc.ac.in"), text, when)

    guide = client.get(f"{API}/courses/{course['id']}/survival-guide").json()
    assert guide["course"]["code"] == "DS 252" and guide["feedback_count"] == 9
    assert [s["term"] for s in guide["semesters"]] == ["Aug 2023", "Aug 2024", "Aug 2025"]
    labels = [s["sentiment"]["label"] for s in guide["semesters"]]
    assert labels[0] == "negative" and labels[-1] == "positive"
    assert guide["trend"] == "improving"
    assert guide["advice"][0] == "Start the project early."
    assert guide["semesters"][0]["highlights"]["negative"].startswith("The pace was brutal")
    assert {t["theme"] for t in guide["themes"]} >= {"workload", "teaching", "grading"}
    assert "DS 252" in guide["summary"] and "improving" in guide["summary"]


def test_survival_guide_semester_boundaries_and_empty_course(client):
    course = _course(client)
    empty = client.get(f"{API}/courses/{course['id']}/survival-guide").json()
    assert empty["feedback_count"] == 0 and empty["overall"] is None and empty["trend"] == "not_enough_data"
    assert empty["semesters"] == [] and "No feedback" in empty["summary"]

    _feedback(client, course["id"], ASHA, "Great course.", "2025-07-31T23:30:00+05:30")   # still the Jan semester (IST)
    _feedback(client, course["id"], RAVI, "Great course.", "2025-07-31T19:00:00+00:00")   # 1 Aug 00:30 IST
    guide = client.get(f"{API}/courses/{course['id']}/survival-guide").json()
    assert [(s["term"], s["feedback_count"]) for s in guide["semesters"]] == [("Jan 2025", 1), ("Aug 2025", 1)]
    assert guide["trend"] == "not_enough_data"
    assert client.get(f"{API}/courses/00000000-0000-0000-0000-000000000000/survival-guide").status_code == 404
