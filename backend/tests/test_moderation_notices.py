"""What owners and moderators are told: reports, moderator decisions, strikes and role changes."""
from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, category, grant, make_admin, sign_in, sql


def _notices(client, who):
    return [n["payload"]["message"] for n in client.get(f"{API}/me/notifications", headers=who).json()["items"]
            if n["type"] == "moderation_action"]


def _listing(client, who, title="Cannabis 10g"):
    cat = category(client, who, "buy-sell", "Misc")
    r = client.post(f"{API}/listings", headers=who, json={"title": title, "price": "500", "category_id": cat})
    assert r.status_code == 201, r.text
    return r.json()


def _setup_moderator(client):
    make_admin(client, ADMIN)
    sign_in(client, MEERA)
    assert grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell").status_code == 201


def test_owner_is_told_once_when_reported_and_never_who_reported(client):
    listing = _listing(client, ASHA)
    for who in (RAVI, KIRAN):
        assert client.post(f"{API}/reports", headers=who, json={
            "target_type": "listing", "target_id": listing["id"], "reason": "Illegal"}).status_code == 201
    [notice] = _notices(client, ASHA)
    assert "Cannabis 10g" in notice and "reported to a moderator" in notice
    assert "Ravi" not in notice and "Kiran" not in notice


def test_moderator_delete_of_a_reported_listing_is_a_strike(client):
    """The bug: deleting from the listing itself soft-deleted it and closed the reports, but no strike."""
    _setup_moderator(client)
    listing = _listing(client, ASHA)
    client.post(f"{API}/reports", headers=RAVI, json={"target_type": "listing", "target_id": listing["id"],
                                                      "reason": "Drugs"})
    r = client.delete(f"{API}/listings/{listing['id']}?reason=Selling%20drugs&severity=severe", headers=MEERA)
    assert r.status_code == 204
    [strike] = client.get(f"{API}/me/seller-strikes", headers=ASHA).json()
    assert strike["severity"] == "severe" and strike["moderator_note"] == "Selling drugs" and strike["listing_hidden"]
    assert "Reason: Selling drugs" in _notices(client, ASHA)[0]
    assert client.get(f"{API}/listings/{listing['id']}").status_code == 404        # hidden from everyone else
    assert sql("SELECT status::text AS s FROM reports")[0]["s"] == "actioned"
    # A severe strike blocks posting.
    assert client.post(f"{API}/listings", headers=ASHA, json={
        "title": "x", "price": "1", "category_id": listing["category"]["id"]}).status_code == 403


def test_moderator_delete_without_a_report_is_no_strike_but_says_why(client):
    _setup_moderator(client)
    listing = _listing(client, ASHA, "Duplicate post")
    assert client.delete(f"{API}/listings/{listing['id']}?reason=Posted%20twice", headers=MEERA).status_code == 204
    assert client.get(f"{API}/me/seller-strikes", headers=ASHA).json() == []
    assert _notices(client, ASHA) == ['A moderator removed your listing "Duplicate post". Reason: Posted twice']


def test_resolving_a_report_tells_the_owner_the_outcome(client):
    _setup_moderator(client)
    keep = _listing(client, ASHA, "Hero cycle")
    remove = _listing(client, ASHA, "Fake iPhone")
    ids = {}
    for item in (keep, remove):
        ids[item["id"]] = client.post(f"{API}/reports", headers=RAVI, json={
            "target_type": "listing", "target_id": item["id"], "reason": "Suspicious"}).json()["id"]
    assert client.post(f"{API}/reports/{ids[keep['id']]}/resolve", headers=MEERA,
                       json={"action": "dismissed"}).status_code == 200
    r = client.post(f"{API}/reports/{ids[remove['id']]}/resolve", headers=MEERA,
                    json={"action": "actioned", "remove_content": True, "note": "Counterfeit"})
    assert r.json()["content_removed"] is True     # severity now defaults to non_severe
    notices = _notices(client, ASHA)
    assert any('"Hero cycle" and kept it up' in n for n in notices)
    assert any('"Fake iPhone"' in n and "Reason: Counterfeit" in n and "strike" in n for n in notices)
    assert len(client.get(f"{API}/me/seller-strikes", headers=ASHA).json()) == 1


def test_report_queue_is_newest_first_with_titles(client):
    _setup_moderator(client)
    first, second = _listing(client, ASHA, "Old report"), _listing(client, ASHA, "New report")
    for item in (first, second):
        client.post(f"{API}/reports", headers=RAVI, json={"target_type": "listing", "target_id": item["id"],
                                                          "reason": "x"})
    items = client.get(f"{API}/reports", headers=MEERA).json()["items"]
    assert [i["target_title"] for i in items] == ["New report", "Old report"]


def test_role_changes_are_announced_to_the_person(client):
    make_admin(client, ADMIN)
    sign_in(client, MEERA)
    g = grant(client, ADMIN, "meera@iisc.ac.in", "lost_found").json()
    assert _notices(client, MEERA) == ["You are now a Lost & Found moderator. Open Moderator Panel from the menu next to your profile."]
    assert client.delete(f"{API}/moderators/{g['id']}", headers=ADMIN).status_code == 204
    assert _notices(client, MEERA)[0] == "You are no longer a Lost & Found moderator."
    meera_id = sign_in(client, MEERA)
    assert client.post(f"{API}/users/{meera_id}/make-admin", headers=ADMIN).status_code == 200
    assert "made you the CampusHub admin" in _notices(client, MEERA)[0]


def test_appeals_reach_moderators_and_decisions_reach_the_seller(client):
    _setup_moderator(client)
    strikes = []
    for title in ("Cannabis 10g", "Vodka bottle"):
        listing = _listing(client, ASHA, title)
        client.post(f"{API}/reports", headers=RAVI, json={"target_type": "listing", "target_id": listing["id"],
                                                          "reason": "Illegal"})
        assert client.delete(f"{API}/listings/{listing['id']}?reason=Prohibited&severity=non_severe",
                             headers=MEERA).status_code == 204
    strikes = client.get(f"{API}/me/seller-strikes", headers=ASHA).json()
    first, second = sorted(strikes, key=lambda s: s["listing_title"])

    # Contesting a strike tells the Buy & Sell moderators and the admin, not the seller or others.
    assert client.post(f"{API}/me/seller-strikes/{first['id']}/appeal", headers=ASHA,
                       json={"message": "It was a photo of a plant"}).status_code == 204
    for moderator in (MEERA, ADMIN):
        assert any('Asha contested the strike for "Cannabis 10g"' in n and "photo of a plant" in n
                   for n in _notices(client, moderator))
    assert not any("contested" in n for n in _notices(client, ASHA) + _notices(client, KIRAN))

    # Overturning tells the seller.
    assert client.post(f"{API}/seller-strikes/{first['id']}/overturn", headers=MEERA,
                       json={"note": "Checked: it's a plant"}).status_code == 204
    assert 'overturned the strike for "Cannabis 10g"' in _notices(client, ASHA)[0]
    assert "Checked: it's a plant" in _notices(client, ASHA)[0]

    # Rejecting an appeal tells the seller too.
    client.post(f"{API}/me/seller-strikes/{second['id']}/appeal", headers=ASHA, json={"message": "Please"})
    assert client.post(f"{API}/seller-strikes/{second['id']}/reject-appeal", headers=MEERA).status_code == 204
    assert 'kept the strike' in _notices(client, ASHA)[0] and "Vodka bottle" in _notices(client, ASHA)[0]

    # Lifting the suspension tells the seller they can post again.
    asha_id = sign_in(client, ASHA)
    sql("UPDATE users SET listing_suspended_at = now(), listing_suspended_reason = 'test' WHERE id = $1::uuid", asha_id)
    assert client.post(f"{API}/users/{asha_id}/lift-listing-suspension", headers=MEERA).status_code == 204
    assert "you can post listings again" in _notices(client, ASHA)[0]
