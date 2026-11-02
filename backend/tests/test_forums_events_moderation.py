"""Rev 17: Events moderators, event forums, Reddit-style forums (votes, sorting, replies to replies),
the placement schedule (talks, online tests, interviews), event posters and the CSV imports."""
from datetime import datetime, timedelta, timezone

import pytest

from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, grant, make_admin, sign_in, sql, upload

NOW = datetime.now(timezone.utc)


@pytest.fixture
def people(client):
    """Admin; Ravi moderates Placement Hub; Meera moderates Events; Asha and Kiran are students."""
    make_admin(client, ADMIN)
    for h in (RAVI, ASHA, MEERA, KIRAN):
        sign_in(client, h)
    assert grant(client, ADMIN, "ravi@iisc.ac.in", "placement_hub").status_code == 201
    r = grant(client, ADMIN, "meera@iisc.ac.in", "events")
    assert r.status_code == 201, r.text
    assert "Events moderator" in client.get(f"{API}/me/notifications", headers=MEERA).text


def _tag(client, name="Food/Mess", headers=ADMIN) -> int:
    r = client.post(f"{API}/event-tags", headers=headers, json={"name": name})
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _event(client, headers, tag_ids, **fields):
    start = NOW + timedelta(days=2)
    body = {"title": "Mess fest", "start_time": start.isoformat(),
            "end_time": (start + timedelta(hours=2)).isoformat(), "tag_ids": tag_ids} | fields
    r = client.post(f"{API}/events", headers=headers, json=body)
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------- events moderators
def test_events_moderator_manages_tags_and_any_event(client, people):
    food = _tag(client, headers=MEERA)                       # an events moderator manages the tag list
    assert client.post(f"{API}/event-tags", headers=ASHA, json={"name": "Music"}).status_code == 403
    event = _event(client, ASHA, [food])
    assert client.get(f"{API}/events/{event['id']}", headers=MEERA).json()["can_edit"] is True
    assert client.get(f"{API}/events/{event['id']}", headers=KIRAN).json()["can_edit"] is False
    assert client.patch(f"{API}/events/{event['id']}", headers=KIRAN, json={"title": "x"}).status_code == 403
    r = client.patch(f"{API}/events/{event['id']}", headers=MEERA, json={"title": "Mess fest (moved)"})
    assert r.status_code == 200 and r.json()["title"] == "Mess fest (moved)"
    assert client.delete(f"{API}/events/{event['id']}", headers=MEERA).status_code == 204
    actions = {r["action"] for r in sql("SELECT action FROM moderation_log")}
    assert {"edit_event", "remove_event"} <= actions


def test_following_a_tag_alerts_on_new_events(client, people):
    """Item 8 of the bug list: follow Food/Mess, someone posts a Food/Mess event, you're notified."""
    food, sports = _tag(client), _tag(client, "Sports")
    assert client.put(f"{API}/me/followed-tags/{food}", headers=KIRAN).status_code == 204
    _event(client, ASHA, [sports], title="Football")                           # not followed: no alert
    event = _event(client, ASHA, [food], title="Biryani night")
    alerts = [n for n in client.get(f"{API}/me/notifications", headers=KIRAN).json()["items"]
              if n["type"] == "followed_tag_event"]
    assert len(alerts) == 1
    assert alerts[0]["payload"]["event_id"] == event["id"] and "Biryani night" in alerts[0]["payload"]["message"]
    # The poster isn't alerted about their own event.
    client.put(f"{API}/me/followed-tags/{food}", headers=ASHA)
    _event(client, ASHA, [food], title="Second helping")
    assert not [n for n in client.get(f"{API}/me/notifications", headers=ASHA).json()["items"]
                if n["type"] == "followed_tag_event"]


def test_event_poster(client, s3, people):
    food = _tag(client)
    key = upload(client, s3, ASHA, "event_poster", content=b"poster", content_type="image/png")
    event = _event(client, ASHA, [food], poster_s3_key=key)
    assert event["poster_url"] and key in event["poster_url"]
    # Someone else's upload can't be attached.
    other = upload(client, s3, KIRAN, "event_poster")
    assert client.patch(f"{API}/events/{event['id']}", headers=ASHA, json={"poster_s3_key": other}).status_code == 422
    r = client.patch(f"{API}/events/{event['id']}", headers=ASHA, json={"poster_s3_key": None})
    assert r.status_code == 200 and r.json()["poster_url"] is None


# ---------------------------------------------------------------- forums
def test_event_forum_and_its_moderation(client, people):
    event = _event(client, ASHA, [_tag(client)])
    forum = client.get(f"{API}/events/{event['id']}/forum").json()
    assert forum["scope_type"] == "event" and forum["event_id"] == event["id"]
    thread = client.post(f"{API}/forums/{forum['id']}/threads", headers=KIRAN,
                         json={"title": "Is it veg-friendly?", "content": "Asking for a friend"}).json()
    # An events moderator moderates event forums; a Placement Hub moderator doesn't.
    assert client.get(f"{API}/threads/{thread['id']}", headers=MEERA).json()["viewer_can_moderate"] is True
    assert client.get(f"{API}/threads/{thread['id']}", headers=RAVI).json()["viewer_can_moderate"] is False
    r = client.post(f"{API}/reports", headers=ASHA, json={"target_type": "thread", "target_id": thread["id"],
                                                          "reason": "spam"})
    assert r.status_code == 201 and r.json()["module"] == "events"
    assert [x["id"] for x in client.get(f"{API}/reports", headers=MEERA).json()["items"]] == [r.json()["id"]]
    assert client.delete(f"{API}/threads/{thread['id']}", headers=MEERA).status_code == 204
    # A cancelled event's forum can't be opened any more.
    other = _event(client, ASHA, [_tag(client, "Sports")])
    client.delete(f"{API}/events/{other['id']}", headers=ASHA)
    assert client.get(f"{API}/events/{other['id']}/forum").status_code == 404


def test_votes_sorting_and_nested_replies(client, people):
    company = client.post(f"{API}/companies", headers=RAVI, json={"name": "Nvidia"}).json()
    forum = client.get(f"{API}/companies/{company['id']}/forum").json()
    post = lambda h, title: client.post(f"{API}/forums/{forum['id']}/threads", headers=h,  # noqa: E731
                                        json={"title": title, "content": f"{title} body"}).json()
    old, new = post(ASHA, "Resume tips"), post(KIRAN, "OA pattern")
    assert old["score"] == 1 and old["viewer_vote"] == 1                  # your own post starts upvoted
    sql("UPDATE threads SET created_at = now() - interval '3 days' WHERE id = $1::uuid", old["id"])
    for h in (RAVI, MEERA):
        assert client.put(f"{API}/threads/{old['id']}/vote", headers=h, json={"value": 1}).json()["score"] in (2, 3)
    r = client.put(f"{API}/threads/{new['id']}/vote", headers=RAVI, json={"value": -1}).json()
    assert r == {"score": 0, "viewer_vote": -1}
    assert client.put(f"{API}/threads/{new['id']}/vote", headers=RAVI, json={"value": 0}).json()["score"] == 1
    assert client.put(f"{API}/threads/{new['id']}/vote", json={"value": 1}).status_code == 401   # guests can't vote

    order = lambda sort: [t["title"] for t in client.get(  # noqa: E731
        f"{API}/forums/{forum['id']}/threads", params={"sort": sort}, headers=RAVI).json()["items"]]
    assert order("new") == ["OA pattern", "Resume tips"]
    assert order("top") == ["Resume tips", "OA pattern"]
    listed = client.get(f"{API}/forums/{forum['id']}/threads", params={"q": "resume"}, headers=RAVI).json()["items"]
    assert [t["title"] for t in listed] == ["Resume tips"]
    assert listed[0]["viewer_vote"] == 1 and listed[0]["preview"] == "Resume tips body"

    top = client.post(f"{API}/threads/{old['id']}/comments", headers=KIRAN, json={"content": "Keep it 1 page"}).json()
    assert top["parent_id"] is None and top["score"] == 1
    child = client.post(f"{API}/threads/{old['id']}/comments", headers=ASHA,
                        json={"content": "Even for PhDs?", "parent_id": top["id"]}).json()
    assert child["parent_id"] == top["id"]
    assert client.put(f"{API}/comments/{top['id']}/vote", headers=RAVI, json={"value": 1}).json()["score"] == 2
    detail = client.get(f"{API}/threads/{old['id']}", headers=RAVI).json()
    assert [c["parent_id"] for c in detail["comments"]] == [None, None, top["id"]]
    assert detail["comments"][1]["viewer_vote"] == 1 and detail["reply_count"] == 2
    # A parent from another thread is refused.
    r = client.post(f"{API}/threads/{new['id']}/comments", headers=ASHA, json={"content": "x", "parent_id": top["id"]})
    assert r.status_code == 422


# ---------------------------------------------------------------- placement schedule and CSV imports
def test_schedule_kinds(client, people):
    company = client.post(f"{API}/companies", headers=RAVI, json={"name": "Google"}).json()
    for kind, days in (("ppt", 3), ("oa", 5), ("interview", 9)):
        r = client.post(f"{API}/companies/{company['id']}/ppts", headers=RAVI, json={
            "kind": kind, "scheduled_at": (NOW + timedelta(days=days)).isoformat(), "venue": "Online"})
        assert r.status_code == 201 and r.json()["kind"] == kind
    assert client.post(f"{API}/companies/{company['id']}/ppts", headers=RAVI,
                       json={"kind": "lunch", "venue": "x"}).status_code == 422
    upcoming = client.get(f"{API}/placement/ppts").json()["items"]
    assert [p["kind"] for p in upcoming] == ["ppt", "oa", "interview"]
    assert [p["kind"] for p in client.get(f"{API}/placement/ppts", params={"kind": ["oa", "interview"]})
            .json()["items"]] == ["oa", "interview"]
    summary = client.get(f"{API}/companies").json()["items"][0]
    assert summary["next_date_kind"] == "ppt" and summary["next_date_at"] == summary["next_ppt_at"]


def test_csv_imports(client, people):
    companies = ("Name,Industry,Website,About\n"
                 "IBM,Software and hardware,https://ibm.com/careers,Big Blue\n"
                 "Nvidia,Semiconductors,,\n"
                 ",Nothing,,\n")
    assert client.post(f"{API}/placement/companies/import", headers=ASHA, json={"csv": companies}).status_code == 403
    r = client.post(f"{API}/placement/companies/import", headers=RAVI, json={"csv": companies})
    assert r.status_code == 201, r.text
    assert r.json() | {"rejected_rows": None} == {
        "rows_total": 3, "rows_created": 2, "rows_updated": 0, "rows_rejected": 1,
        "companies_created": ["IBM", "Nvidia"], "rejected_rows": None}
    r = client.post(f"{API}/placement/companies/import", headers=RAVI, json={"csv": "Name,Industry\nibm,Consulting\n"})
    assert r.json()["rows_updated"] == 1
    ibm = sql("SELECT industry, website FROM companies WHERE name = 'IBM'")[0]
    assert dict(ibm) == {"industry": "Consulting", "website": "https://ibm.com/careers"}

    future = (NOW + timedelta(days=10)).strftime("%d/%m/%Y")
    schedule = ("Company\tType\tDate\tTime\tVenue\tDetails\n"
                f"IBM\tOA\t{future}\t6:00 pm\tHackerRank\t90 minutes\n"
                f"Microsoft\tInterview\t{future}\t10:00\tCDS\t\n"
                f"IBM\tLunch\t{future}\t\t\t\n")
    r = client.post(f"{API}/placement/schedule/import", headers=RAVI, json={"csv": schedule})
    assert r.status_code == 201, r.text
    body = r.json()
    assert (body["rows_created"], body["rows_rejected"], body["companies_created"]) == (2, 1, ["Microsoft"])
    assert body["rejected_rows"][0]["line"] == 4
    # Importing the same file again updates instead of duplicating.
    assert client.post(f"{API}/placement/schedule/import", headers=RAVI,
                       json={"csv": schedule}).json()["rows_updated"] == 2
    oa = [p for p in client.get(f"{API}/placement/ppts").json()["items"] if p["kind"] == "oa"][0]
    at = datetime.fromisoformat(oa["scheduled_at"]).astimezone(timezone(timedelta(hours=5, minutes=30)))
    assert (oa["company_name"], at.hour, oa["venue"]) == ("IBM", 18, "HackerRank")
    r = client.post(f"{API}/placement/schedule/import", headers=RAVI, json={"csv": "Venue\nx\n"})
    assert r.status_code == 422 and "Company" in r.json()["detail"]


def test_moderator_grant_for_events_module_only(client, people):
    r = grant(client, ADMIN, "kiran@iisc.ac.in", "events", scope_type="department",
              department_id="00000000-0000-0000-0000-000000000000")
    assert r.status_code == 422
