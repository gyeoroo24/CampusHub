from .conftest import API, ASHA, MEERA, RAVI, category, grant, make_admin, sign_in, sql, upload, ADMIN


def _listing(client, headers, cat, **fields):
    body = {"title": "Hero cycle", "description": "Good condition, new tyres", "price": "2500",
            "category_id": cat, "location": "Hostel C"} | fields
    r = client.post(f"{API}/listings", headers=headers, json=body)
    assert r.status_code == 201, r.text
    return r.json()


def test_create_listing_with_photos_and_contact_rules(client, s3):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    front = upload(client, s3, ASHA, "listing_photo", b"front")
    side = upload(client, s3, ASHA, "listing_photo", b"side")
    listing = _listing(client, ASHA, cycles, photo_keys=[front, side])
    assert [p["s3_key"] for p in listing["photos"]] == [front, side]
    assert listing["status"] == "available"

    guest_view = client.get(f"{API}/listings/{listing['id']}").json()
    assert guest_view["seller_contact"] is None and guest_view["cover_photo_url"]
    signed_in_view = client.get(f"{API}/listings/{listing['id']}", headers=RAVI).json()
    assert signed_in_view["seller_contact"]["email"] == "asha@iisc.ac.in"


def test_combined_filter_has_no_false_positives(client):
    """FR-6: category + price range + keyword."""
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    books = category(client, ASHA, "buy-sell", "Books")
    _listing(client, ASHA, cycles, title="Hero cycle", price="2500")
    _listing(client, ASHA, cycles, title="Firefox cycle", price="9000")
    _listing(client, ASHA, books, title="Cycle repair manual", price="300")
    _listing(client, RAVI, cycles, title="Bicycle lock", description="sturdy", price="2000")
    r = client.get(f"{API}/listings", params={"category_id": cycles, "min_price": 1000, "max_price": 5000,
                                              "q": "cycle"}).json()
    assert [i["title"] for i in r["items"]] == ["Hero cycle"]


def test_photo_rules(client, s3):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    ravis_photo = upload(client, s3, RAVI, "listing_photo")
    r = client.post(f"{API}/listings", headers=ASHA, json={
        "title": "x", "price": "1", "category_id": cycles, "photo_keys": [ravis_photo]})
    assert r.status_code == 422  # someone else's upload
    asha_id = sign_in(client, ASHA)
    r = client.post(f"{API}/listings", headers=ASHA, json={
        "title": "x", "price": "1", "category_id": cycles, "photo_keys": [f"listings/{asha_id}/never-uploaded.jpg"]})
    assert r.status_code == 422  # ticket issued but file never uploaded
    too_many = [upload(client, s3, ASHA, "listing_photo", bytes([i])) for i in range(11)]
    r = client.post(f"{API}/listings", headers=ASHA, json={
        "title": "x", "price": "1", "category_id": cycles, "photo_keys": too_many})
    assert r.status_code == 422


def test_reorder_and_remove_photos(client, s3):
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    a, b, c = (upload(client, s3, ASHA, "listing_photo", x) for x in (b"a", b"b", b"c"))
    listing = _listing(client, ASHA, cycles, photo_keys=[a, b, c])
    r = client.put(f"{API}/listings/{listing['id']}/photos", headers=ASHA, json={"photo_keys": [c, a]})
    assert [p["s3_key"] for p in r.json()["photos"]] == [c, a]
    assert client.put(f"{API}/listings/{listing['id']}/photos", headers=RAVI,
                      json={"photo_keys": []}).status_code == 403


def test_only_seller_changes_status(client):
    """FR-5."""
    listing = _listing(client, ASHA, category(client, ASHA, "buy-sell", "Cycles"))
    url = f"{API}/listings/{listing['id']}/status"
    assert client.patch(url, headers=RAVI, json={"status": "sold"}).status_code == 403
    assert client.patch(url, headers=ASHA, json={"status": "reserved"}).json()["status"] == "reserved"
    assert client.patch(f"{API}/listings/{listing['id']}", headers=RAVI, json={"price": "1"}).status_code == 403


def test_moderator_removes_listing_and_revoked_moderator_cannot(client):
    """FR-10 and FR-3."""
    make_admin(client, ADMIN)
    sign_in(client, MEERA)
    cycles = category(client, ASHA, "buy-sell", "Cycles")
    first, second = _listing(client, ASHA, cycles), _listing(client, ASHA, cycles, title="Lamp")
    assert client.delete(f"{API}/listings/{first['id']}", headers=RAVI).status_code == 403

    g = grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell")
    assert g.status_code == 201
    assert client.delete(f"{API}/listings/{first['id']}", headers=MEERA,
                         params={"reason": "prohibited item"}).status_code == 204
    assert client.get(f"{API}/listings/{first['id']}").status_code == 404
    assert first["id"] not in [i["id"] for i in client.get(f"{API}/listings").json()["items"]]
    log = sql("SELECT action, reason FROM moderation_log WHERE target_id = $1::uuid", first["id"])
    assert log[0]["action"] == "remove_listing" and log[0]["reason"] == "prohibited item"

    assert client.delete(f"{API}/moderators/{g.json()['id']}", headers=ADMIN).status_code == 204
    assert client.delete(f"{API}/listings/{second['id']}", headers=MEERA).status_code == 403
    # re-granting after a revoke works
    assert grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell").status_code == 201
    assert grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell").status_code == 409


def test_delete_is_permanent(client):
    """Deleting a listing removes it, its reports and watches from the database (rev 23), even when a
    report is still open; a chat about it stays, showing the listing as removed under its old title."""
    listing = _listing(client, ASHA, category(client, ASHA, "buy-sell", "Cycles"))
    lid = listing["id"]
    assert client.post(f"{API}/reports", headers=RAVI, json={
        "target_type": "listing", "target_id": lid, "reason": "looks stolen"}).status_code == 201
    assert client.put(f"{API}/listings/{lid}/watch", headers=RAVI).status_code == 204
    chat = client.post(f"{API}/chat/conversations", headers=RAVI, json={"listing_id": lid})
    assert chat.status_code == 201, chat.text

    assert client.delete(f"{API}/listings/{lid}", headers=ASHA).status_code == 204
    assert sql("SELECT count(*) AS n FROM listings WHERE id = $1::uuid", lid)[0]["n"] == 0
    assert sql("SELECT count(*) AS n FROM reports WHERE target_id = $1::uuid", lid)[0]["n"] == 0
    assert sql("SELECT count(*) AS n FROM listing_watches WHERE listing_id = $1::uuid", lid)[0]["n"] == 0
    assert client.delete(f"{API}/listings/{lid}", headers=ASHA).status_code == 404
    topic = next(t for t in client.get(f"{API}/chat/conversations/{chat.json()['conversation']['id']}",
                                       headers=RAVI).json()["topics"] if t["ref_id"] == lid)
    assert topic["is_removed"] and topic["title"] == listing["title"]
    assert str(topic["owner_id"]) == sign_in(client, ASHA)


def test_strike_outlives_deleted_listing(client):
    """A seller deleting a listing a moderator removed doesn't erase the strike: it keeps the title."""
    make_admin(client, ADMIN)
    listing = _listing(client, ASHA, category(client, ASHA, "buy-sell", "Cycles"))
    client.post(f"{API}/reports", headers=RAVI, json={
        "target_type": "listing", "target_id": listing["id"], "reason": "counterfeit"})
    assert client.delete(f"{API}/listings/{listing['id']}", headers=ADMIN).status_code == 204   # strike + hide
    assert client.delete(f"{API}/listings/{listing['id']}", headers=ASHA).status_code == 204    # gone for good
    assert sql("SELECT count(*) AS n FROM listings WHERE id = $1::uuid", listing["id"])[0]["n"] == 0
    strikes = client.get(f"{API}/me/seller-strikes", headers=ASHA).json()
    assert [(s["listing_id"], s["listing_title"]) for s in strikes] == [(None, listing["title"])]
