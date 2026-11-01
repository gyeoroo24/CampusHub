"""Community Events (FR-18 to FR-20, FR-22): tags, Past/Present/Upcoming, bookmarks, followed tags
and the alerts they trigger."""
from datetime import datetime, timedelta, timezone

import pytest

from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, category, make_admin, sign_in

NOW = datetime.now(timezone.utc)


def _iso(delta: timedelta) -> str:
    return (NOW + delta).isoformat()


@pytest.fixture
def tags(client):
    make_admin(client, ADMIN)
    for h in (ASHA, RAVI, MEERA, KIRAN):
        sign_in(client, h)
    out = {}
    for name in ("Sports", "Photography", "Culture"):
        r = client.post(f"{API}/event-tags", headers=ADMIN, json={"name": name})
        assert r.status_code == 201, r.text
        out[name] = r.json()["id"]
    return out


def _event(client, headers, tag_ids, start=timedelta(days=2), hours=2, **fields):
    body = {"title": "Bird walk", "location": "Main gate", "start_time": _iso(start),
            "end_time": _iso(start + timedelta(hours=hours)), "tag_ids": tag_ids} | fields
    r = client.post(f"{API}/events", headers=headers, json=body)
    assert r.status_code == 201, r.text
    return r.json()


def _alerts(client, headers, kind):
    return [n["payload"] for n in client.get(f"{API}/me/notifications", headers=headers).json()["items"]
            if n["type"] == kind]


def test_tags_are_admin_managed(client, tags):
    assert client.post(f"{API}/event-tags", headers=ASHA, json={"name": "Food/Mess"}).status_code == 403
    assert client.post(f"{API}/event-tags", headers=ADMIN, json={"name": "Sports"}).status_code == 409
    r = client.patch(f"{API}/event-tags/{tags['Culture']}", headers=ADMIN, json={"name": "Culture & Arts"})
    assert r.status_code == 200 and r.json()["name"] == "Culture & Arts"
    assert [t["name"] for t in client.get(f"{API}/event-tags").json()] == ["Culture & Arts", "Photography", "Sports"]


def test_events_classify_by_time_and_filter_by_tag(client, tags):
    """FR-19: Past/Present/Upcoming from the clock; FR-18: filter by tag returns only events carrying it."""
    past = _event(client, ASHA, [tags["Sports"]], start=timedelta(days=-3), title="Cricket final")
    now = _event(client, ASHA, [tags["Photography"]], start=timedelta(hours=-1), title="Photo walk")
    soon = _event(client, RAVI, [tags["Sports"], tags["Culture"]], start=timedelta(days=1), title="Cyclothon")
    later = _event(client, RAVI, [tags["Culture"]], start=timedelta(days=9), title="Diwali night")
    assert (past["when"], now["when"], soon["when"], later["when"]) == ("past", "present", "upcoming", "upcoming")

    ids = lambda **p: [e["id"] for e in client.get(f"{API}/events", params=p).json()["items"]]  # noqa: E731
    assert ids() == [now["id"], soon["id"], later["id"]]                      # default: present, then upcoming
    assert ids(when="past") == [past["id"]]
    assert ids(when=["past", "upcoming", "present"]) == [now["id"], soon["id"], later["id"], past["id"]]
    assert ids(tag_id=tags["Sports"], when=["past", "upcoming"]) == [soon["id"], past["id"]]
    assert ids(tag_id=[tags["Photography"], tags["Culture"]]) == [now["id"], soon["id"], later["id"]]
    assert ids(q="diwali") == [later["id"]]
    assert ids(to_time=_iso(timedelta(days=2))) == [now["id"], soon["id"]]
    assert ids(organizer_id=past["organizer"]["id"], when="past") == [past["id"]]
    assert [t["name"] for t in soon["tags"]] == ["Culture", "Sports"]
    assert {t["name"]: t["upcoming_count"] for t in client.get(f"{API}/event-tags").json()} == \
        {"Culture": 2, "Photography": 1, "Sports": 1}


def test_event_validation_and_ownership(client, tags):
    bad = {"title": "x", "start_time": _iso(timedelta(days=2)), "end_time": _iso(timedelta(days=1)),
           "tag_ids": [tags["Sports"]]}
    assert client.post(f"{API}/events", headers=ASHA, json=bad).status_code == 422          # ends before it starts
    assert client.post(f"{API}/events", headers=ASHA, json=bad | {
        "end_time": _iso(timedelta(days=40))}).status_code == 422                            # longer than 30 days
    assert client.post(f"{API}/events", headers=ASHA, json=bad | {
        "end_time": _iso(timedelta(days=3)), "tag_ids": []}).status_code == 422             # needs a tag
    assert client.post(f"{API}/events", headers=ASHA, json=bad | {
        "end_time": _iso(timedelta(days=3)), "tag_ids": [999]}).status_code == 422          # unknown tag
    assert client.post(f"{API}/events", headers=ASHA, json=bad | {
        "start_time": "2026-12-01T10:00:00", "end_time": "2026-12-01T12:00:00"}).status_code == 422   # no timezone
    assert client.post(f"{API}/events", json=bad).status_code == 401                          # guests read only

    event = _event(client, ASHA, [tags["Sports"]])
    assert event["can_edit"] is True
    assert client.get(f"{API}/events/{event['id']}", headers=RAVI).json()["can_edit"] is False
    assert client.patch(f"{API}/events/{event['id']}", headers=RAVI, json={"title": "x"}).status_code == 403
    assert client.delete(f"{API}/events/{event['id']}", headers=RAVI).status_code == 403
    assert client.patch(f"{API}/events/{event['id']}", headers=ASHA,
                        json={"end_time": _iso(timedelta(days=1))}).status_code == 422       # before the start
    r = client.patch(f"{API}/events/{event['id']}", headers=ADMIN, json={"title": "Bird walk (rescheduled)"})
    assert r.status_code == 200 and r.json()["can_edit"] is True
    assert client.delete(f"{API}/events/{event['id']}", headers=ADMIN).status_code == 204
    assert client.get(f"{API}/events/{event['id']}").status_code == 404


def test_followed_tag_alerts_on_new_and_newly_tagged_events(client, tags):
    """FR-20 followed tag: a new event with a tag you follow alerts you; your own and past events don't."""
    assert client.put(f"{API}/me/followed-tags/{tags['Photography']}", headers=MEERA).status_code == 204
    assert client.put(f"{API}/me/followed-tags/{tags['Photography']}", headers=MEERA).status_code == 204   # twice is fine
    assert client.put(f"{API}/me/followed-tags/{tags['Photography']}", headers=ASHA).status_code == 204
    assert client.put(f"{API}/me/followed-tags/999", headers=MEERA).status_code == 404
    assert [t["name"] for t in client.get(f"{API}/me/followed-tags", headers=MEERA).json()] == ["Photography"]
    assert {t["name"]: t["following"] for t in client.get(f"{API}/event-tags", headers=MEERA).json()}["Photography"]

    walk = _event(client, ASHA, [tags["Photography"]], title="Heritage photo walk")
    _event(client, KIRAN, [tags["Photography"]], start=timedelta(days=-5), title="Old walk")    # already over
    _event(client, KIRAN, [tags["Sports"]], title="Cricket")                                     # not followed
    alerts = _alerts(client, MEERA, "followed_tag_event")
    assert [a["event_id"] for a in alerts] == [walk["id"]]
    assert "Photography" in alerts[0]["message"] and "Heritage photo walk" in alerts[0]["message"]
    assert _alerts(client, ASHA, "followed_tag_event") == []                                     # own event

    # Adding a followed tag to an existing event alerts its followers too.
    cricket = client.get(f"{API}/events", params={"q": "Cricket"}).json()["items"][0]
    client.patch(f"{API}/events/{cricket['id']}", headers=KIRAN,
                 json={"tag_ids": [tags["Sports"], tags["Photography"]]})
    assert [a["event_id"] for a in _alerts(client, MEERA, "followed_tag_event")] == [cricket["id"], walk["id"]]

    assert client.delete(f"{API}/me/followed-tags/{tags['Photography']}", headers=MEERA).status_code == 204
    _event(client, ASHA, [tags["Photography"]], title="Night sky photography")
    assert len(_alerts(client, MEERA, "followed_tag_event")) == 2


def test_bookmarked_event_update_and_cancel_alerts(client, tags):
    """FR-20 / FR-22: bookmark an event; get notified when it changes or is cancelled."""
    event = _event(client, ASHA, [tags["Culture"]], title="Diwali night")
    assert client.put(f"{API}/me/bookmarks/event/{event['id']}", headers=MEERA).status_code == 200
    assert client.put(f"{API}/me/bookmarks/event/{event['id']}", headers=MEERA).status_code == 200   # idempotent
    client.put(f"{API}/me/bookmarks/event/{event['id']}", headers=ASHA)                            # the organizer
    detail = client.get(f"{API}/events/{event['id']}", headers=MEERA).json()
    assert detail["is_bookmarked"] is True and detail["bookmark_count"] == 2
    assert client.get(f"{API}/events/{event['id']}").json()["is_bookmarked"] is False             # guest
    assert [e["id"] for e in client.get(f"{API}/events", params={"bookmarked": True},
                                        headers=MEERA).json()["items"]] == [event["id"]]
    assert client.get(f"{API}/events", params={"bookmarked": True}).status_code == 401

    # Same values again: nothing changed, no alert.
    client.patch(f"{API}/events/{event['id']}", headers=ASHA, json={"title": "Diwali night"})
    assert _alerts(client, MEERA, "bookmarked_event_update") == []
    client.patch(f"{API}/events/{event['id']}", headers=ASHA, json={
        "location": "Students' Gymkhana", "start_time": _iso(timedelta(days=3)), "end_time": _iso(timedelta(days=3, hours=3))})
    update = _alerts(client, MEERA, "bookmarked_event_update")
    assert len(update) == 1 and "Gymkhana" in update[0]["message"] and update[0]["cancelled"] is False
    assert _alerts(client, ASHA, "bookmarked_event_update") == []                                 # own change

    assert client.delete(f"{API}/events/{event['id']}", headers=ASHA).status_code == 204
    cancelled = _alerts(client, MEERA, "bookmarked_event_update")[0]
    assert cancelled["cancelled"] is True and "cancelled" in cancelled["message"]
    assert client.get(f"{API}/me/bookmarks", headers=MEERA).json() == []


def test_bookmarks_for_listings_and_guest_import(client, tags):
    """Bookmarks: account-synced for signed-in users; a guest's on-device ones are imported after sign-in."""
    cat = category(client, ADMIN, "buy-sell", "Cycles")
    listing = client.post(f"{API}/listings", headers=RAVI, json={
        "title": "Hero cycle", "description": "Good", "price": "2500", "category_id": cat}).json()
    event = _event(client, RAVI, [tags["Sports"]])
    gone = _event(client, RAVI, [tags["Sports"]], title="Cancelled")
    client.delete(f"{API}/events/{gone['id']}", headers=RAVI)
    assert client.put(f"{API}/me/bookmarks/event/{gone['id']}", headers=KIRAN).status_code == 404
    assert client.put(f"{API}/me/bookmarks/listing/{listing['id']}", headers=KIRAN).status_code == 200

    r = client.post(f"{API}/me/bookmarks/import", headers=KIRAN, json={"items": [
        {"target_type": "event", "target_id": event["id"]},
        {"target_type": "event", "target_id": event["id"]},
        {"target_type": "event", "target_id": gone["id"]},
        {"target_type": "listing", "target_id": listing["id"]}]})
    assert r.json() == {"added": 1, "already_saved": 1, "skipped": 1}
    saved = client.get(f"{API}/me/bookmarks", headers=KIRAN).json()
    assert {(b["target_type"], b["target_id"]) for b in saved} == {("event", event["id"]), ("listing", listing["id"])}
    assert [b["target_id"] for b in client.get(f"{API}/me/bookmarks", params={"target_type": "listing"},
                                              headers=KIRAN).json()] == [listing["id"]]
    # A removed listing drops out of the list.
    client.delete(f"{API}/listings/{listing['id']}", headers=RAVI)
    assert [b["target_type"] for b in client.get(f"{API}/me/bookmarks", headers=KIRAN).json()] == ["event"]
    assert client.delete(f"{API}/me/bookmarks/event/{event['id']}", headers=KIRAN).status_code == 204
    assert client.get(f"{API}/me/bookmarks", headers=KIRAN).json() == []
