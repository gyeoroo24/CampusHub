"""Rev 26: unblocking a seller, bookmarks, deleting a category with its posts, and merging similar companies."""
import json

from app.company_matching import group_similar, suggested_name

from .conftest import ADMIN, API, ASHA, KIRAN, RAVI, category, grant, make_admin, sign_in, sql


def _listing(client, headers, cat, title="Cycle"):
    r = client.post(f"{API}/listings", headers=headers, json={"title": title, "price": "1000", "category_id": cat})
    assert r.status_code == 201, r.text
    return r.json()


def _block(client, seller, cat):
    """A moderator removes a reported listing with a severe strike: the seller is blocked at once."""
    listing = _listing(client, seller, cat)
    client.post(f"{API}/reports", headers=RAVI, json={
        "target_type": "listing", "target_id": listing["id"], "reason": "illegal"})
    assert client.delete(f"{API}/listings/{listing['id']}?severity=severe", headers=ADMIN).status_code == 204
    return listing


def _messages(user_id):
    return [json.loads(r["payload"])["message"] for r in sql(
        "SELECT payload FROM notifications WHERE user_id = $1::uuid ORDER BY created_at", user_id)]


# ---------------------------------------------------------------- unblocking a seller
def test_a_blocked_seller_asks_to_be_unblocked_and_a_moderator_approves(client):
    make_admin(client, ADMIN)
    asha = sign_in(client, ASHA)
    sign_in(client, KIRAN)
    assert grant(client, ADMIN, "kiran@iisc.ac.in", "buy_sell").status_code == 201
    cat = category(client, ASHA, "buy-sell", "Cycles")

    # Not blocked: nothing to ask for.
    assert client.post(f"{API}/me/seller-unblock-request", headers=ASHA, json={"message": "hi"}).status_code == 409
    _block(client, ASHA, cat)
    assert client.get(f"{API}/me/seller-strikes/summary", headers=ASHA).json()["suspended"]

    r = client.post(f"{API}/me/seller-unblock-request", headers=ASHA, json={"message": "It was a toy, sorry."})
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "pending"
    assert client.post(f"{API}/me/seller-unblock-request", headers=ASHA, json={"message": "again"}).status_code == 409
    kiran = sign_in(client, KIRAN)
    assert any("asked to be unblocked" in m for m in _messages(kiran))

    # Only Buy & Sell moderators see the queue.
    assert client.get(f"{API}/seller-unblock-requests", headers=RAVI).status_code == 403
    queue = client.get(f"{API}/seller-unblock-requests", headers=KIRAN).json()
    assert [q["seller"]["id"] for q in queue] == [asha]
    blocked = client.get(f"{API}/blocked-sellers", headers=KIRAN).json()
    assert [(b["seller"]["id"], b["strikes"], b["suspended"]) for b in blocked] == [(asha, 1, True)]
    assert blocked[0]["pending_request"]["id"] == queue[0]["id"]

    assert client.post(f"{API}/seller-unblock-requests/{queue[0]['id']}/approve", headers=KIRAN,
                       json={"note": "First time"}).status_code == 204
    summary = client.get(f"{API}/me/seller-strikes/summary", headers=ASHA).json()
    assert (summary["strikes"], summary["tag"], summary["suspended"]) == (0, None, False)
    assert client.get(f"{API}/me/seller-unblock-request", headers=ASHA).json()["status"] == "approved"
    assert any("unblocked you as a seller and reset your strikes" in m for m in _messages(asha))
    assert client.get(f"{API}/blocked-sellers", headers=KIRAN).json() == []
    _listing(client, ASHA, cat, "Lamp")   # can post again


def test_a_moderator_unblocks_directly_or_rejects_a_request(client):
    make_admin(client, ADMIN)
    asha = sign_in(client, ASHA)
    cat = category(client, ASHA, "buy-sell", "Cycles")
    _block(client, ASHA, cat)
    request = client.post(f"{API}/me/seller-unblock-request", headers=ASHA, json={"message": "please"}).json()
    assert client.post(f"{API}/seller-unblock-requests/{request['id']}/reject", headers=ADMIN,
                       json={"note": "Too serious"}).status_code == 204
    assert client.get(f"{API}/me/seller-unblock-request", headers=ASHA).json()["status"] == "rejected"
    assert any("kept the block" in m for m in _messages(asha))
    assert client.get(f"{API}/me/seller-strikes/summary", headers=ASHA).json()["suspended"]

    assert client.post(f"{API}/users/{asha}/unblock", headers=RAVI).status_code == 403
    assert client.post(f"{API}/users/{asha}/unblock", headers=ADMIN).status_code == 204
    assert not client.get(f"{API}/me/seller-strikes/summary", headers=ASHA).json()["suspended"]
    assert all(s["excluded"] for s in client.get(f"{API}/me/seller-strikes", headers=ASHA).json())


# ---------------------------------------------------------------- bookmarks
def test_bookmarks(client):
    sign_in(client, ASHA)
    cat = category(client, ASHA, "buy-sell", "Cycles")
    cycle, lamp, desk = (_listing(client, ASHA, cat, t)["id"] for t in ("Cycle", "Lamp", "Desk"))

    # A guest's bookmarks stay on their device; the server looks them up by id.
    found = client.post(f"{API}/listings/lookup", json={"listing_ids": [lamp, cycle, lamp]}).json()
    assert [l["id"] for l in found] == [lamp, cycle]
    assert client.put(f"{API}/listings/{cycle}/bookmark").status_code == 401

    assert client.put(f"{API}/listings/{cycle}/bookmark", headers=RAVI).status_code == 204
    assert client.put(f"{API}/listings/{cycle}/bookmark", headers=RAVI).status_code == 204   # idempotent
    # Signing in copies the guest's bookmarks to the account.
    assert client.post(f"{API}/me/bookmarked-listings", headers=RAVI, json={"listing_ids": [lamp, desk]}).status_code == 204
    assert set(client.get(f"{API}/me/bookmarked-listing-ids", headers=RAVI).json()) == {cycle, lamp, desk}
    assert client.delete(f"{API}/listings/{lamp}/bookmark", headers=RAVI).status_code == 204
    items = client.get(f"{API}/me/bookmarked-listings", headers=RAVI).json()["items"]
    assert [i["id"] for i in items] == [desk, cycle]
    # A deleted listing drops out.
    assert client.delete(f"{API}/listings/{desk}", headers=ASHA).status_code == 204
    assert client.get(f"{API}/me/bookmarked-listing-ids", headers=RAVI).json() == [cycle]


# ---------------------------------------------------------------- deleting a category with its posts
def test_deleting_a_category_with_its_posts(client):
    make_admin(client, ADMIN)
    asha = sign_in(client, ASHA)
    bottle = category(client, ASHA, "buy-sell", "Bottle")
    keep = category(client, ASHA, "buy-sell", "Cycles")
    gone = _listing(client, ASHA, bottle, "Steel bottle")["id"]
    stays = _listing(client, ASHA, keep, "Cycle")["id"]
    assert client.delete(f"{API}/buy-sell/categories/{bottle}", headers=ADMIN).status_code == 409
    assert client.delete(f"{API}/buy-sell/categories/{bottle}?delete_posts=true&move_to={keep}",
                         headers=ADMIN).status_code == 422
    assert client.delete(f"{API}/buy-sell/categories/{bottle}?delete_posts=true", headers=ADMIN).status_code == 204
    assert sql("SELECT count(*) AS n FROM listings WHERE id = $1::uuid", gone)[0]["n"] == 0
    assert sql("SELECT count(*) AS n FROM listings WHERE id = $1::uuid", stays)[0]["n"] == 1
    assert sql("SELECT count(*) AS n FROM bs_categories WHERE id = $1", bottle)[0]["n"] == 0
    assert any("removed your posts in it" in m for m in _messages(asha))


def test_deleting_a_lost_and_found_category_with_its_reports(client):
    make_admin(client, ADMIN)
    sign_in(client, ASHA)
    wallet = category(client, ASHA, "lost-found", "Wallet")
    r = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "title": "Black wallet", "description": "Black leather wallet", "category_id": wallet,
        "occurred_at": "2026-11-01T10:00:00Z", "location": "Library"})
    assert r.status_code == 201, r.text
    assert client.delete(f"{API}/lost-found/categories/{wallet}?delete_posts=true", headers=ADMIN).status_code == 204
    row = sql("SELECT deleted_at, category_id FROM lost_reports WHERE id = $1::uuid", r.json()["id"])[0]
    assert row["deleted_at"] is not None and row["category_id"] is None
    assert client.get(f"{API}/lost-reports/{r.json()['id']}").status_code == 404


# ---------------------------------------------------------------- similar companies
def test_similar_company_names_are_grouped():
    names = ["Accenture", "Accenture [Mock Assessment]", "Accenture (Final Assessment)", "oserve.ai", "Observe AI",
             "Amazon", "Amazon Web Services", "Goldman Sachs", "Intel", "Intuit", "Meta"]
    groups = [[names[i] for i in g] for g in group_similar(dict(enumerate(names)))]
    assert groups == [["Accenture", "Accenture [Mock Assessment]", "Accenture (Final Assessment)"],
                      ["oserve.ai", "Observe AI"]]
    assert suggested_name(groups[0]) == "Accenture"
    assert suggested_name(["oserve.ai", "Observe AI"], [1, 5]) == "Observe AI"


def test_import_shows_similar_companies_and_merging_clubs_them(client):
    make_admin(client, ADMIN)
    for h in (RAVI, ASHA):
        sign_in(client, h)
    assert grant(client, ADMIN, "ravi@iisc.ac.in", "placement_hub").status_code == 201
    sheet = ("Company,Student email,Role\n"
             "Accenture,a@iisc.ac.in,Analyst\n"
             "Accenture [Mock Assessment],b@iisc.ac.in,Analyst\n"
             "Accenture (Final Assessment),c@iisc.ac.in,Consultant\n"
             "Walmart,d@iisc.ac.in,SWE\n")
    result = client.post(f"{API}/placement/imports", headers=RAVI, json={"placement_year": 2026, "sheet": sheet}).json()
    assert len(result["similar_companies"]) == 1
    group = result["similar_companies"][0]
    assert group["suggested_name"] == "Accenture"
    ids = [c["id"] for c in group["companies"]]
    assert len(ids) == 3
    # Give two of them a forum thread each, to check the threads end up together.
    for cid in ids[:2]:
        forum = client.get(f"{API}/companies/{cid}/forum").json()
        assert client.post(f"{API}/forums/{forum['id']}/threads", headers=ASHA,
                           json={"title": "Prep tips", "content": "Any tips?"}).status_code == 201

    assert client.post(f"{API}/placement/companies/merge", headers=ASHA,
                       json={"company_ids": ids, "name": "Accenture"}).status_code == 403
    assert client.post(f"{API}/placement/companies/merge", headers=RAVI,
                       json={"company_ids": ids[:1], "name": "Accenture"}).status_code == 422
    r = client.post(f"{API}/placement/companies/merge", headers=RAVI, json={"company_ids": ids, "name": "Accenture"})
    assert r.status_code == 200, r.text
    merged = r.json()
    assert merged["name"] == "Accenture" and merged["total_selected"] == 3
    assert [c["name"] for c in sql("SELECT name FROM companies ORDER BY name")] == ["Accenture", "Walmart"]
    forum = client.get(f"{API}/companies/{merged['id']}/forum").json()
    assert sql("SELECT count(*) AS n FROM threads WHERE forum_id = $1::uuid", forum["id"])[0]["n"] == 2
    assert client.get(f"{API}/placement/companies/similar", headers=RAVI).json() == []

    # Merging into a name that one of the merged companies already has keeps that company.
    walmart = sql("SELECT id::text FROM companies WHERE name = 'Walmart'")[0]["id"]
    assert client.post(f"{API}/placement/companies/merge", headers=RAVI,
                       json={"company_ids": [merged["id"], walmart], "name": "Walmart"}).status_code == 200


def test_adding_companies_or_dates_also_flags_similar_companies(client):
    """The same review as the placement sheet, after Add companies and Add placement dates (form or file)."""
    make_admin(client, ADMIN)
    sign_in(client, RAVI)
    assert grant(client, ADMIN, "ravi@iisc.ac.in", "placement_hub").status_code == 201
    r = client.post(f"{API}/placement/companies/import", headers=RAVI,
                    json={"csv": "Name,Industry\nInfosys,IT\nInfosys [Mock Assessment],IT\nWalmart,Retail\n"}).json()
    assert [[c["name"] for c in g["companies"]] for g in r["similar_companies"]] == [
        ["Infosys", "Infosys [Mock Assessment]"]]
    r = client.post(f"{API}/placement/schedule/import", headers=RAVI, json={
        "csv": "Company,Type,Date,Time\nWalmart Inc.,PPT,2026-12-01,10:00\n", "file_name": "ppt.csv"}).json()
    assert r["companies_created"] == ["Walmart Inc."]
    assert [sorted(c["name"] for c in g["companies"]) for g in r["similar_companies"]] == [
        ["Walmart", "Walmart Inc."]]
    # The form adds one company; the app then asks about just that one.
    client.post(f"{API}/companies", headers=RAVI, json={"name": "Wipro"})
    new = client.post(f"{API}/companies", headers=RAVI, json={"name": "Wipro [Mock Assessment]"}).json()
    groups = client.get(f"{API}/placement/companies/similar", headers=RAVI, params={"company_id": new["id"]}).json()
    assert [sorted(c["name"] for c in g["companies"]) for g in groups] == [["Wipro", "Wipro [Mock Assessment]"]]
    assert len(client.get(f"{API}/placement/companies/similar", headers=RAVI).json()) == 3
