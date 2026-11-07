"""Fixes from the 2026-11 red-team audit (EDGE-01/02/03, API-01, SEC-01, DI-01/02/03, FUNC-02)."""
import json

from .conftest import ADMIN, API, ASHA, BUCKET, MEERA, RAVI, category, grant, make_admin, sign_in, sql, upload


def _listing(client, headers, cat, title="Cycle", **extra):
    r = client.post(f"{API}/listings", headers=headers, json={"title": title, "price": "1000", "category_id": cat} | extra)
    assert r.status_code == 201, r.text
    return r.json()


def _raw(client, method, path, headers, body: str):
    return client.request(method, f"{API}{path}", headers=headers | {"Content-Type": "application/json"}, content=body)


# ---------------------------------------------------------------- EDGE-01: NaN / Infinity prices
def test_non_finite_prices_get_422_not_500(client):
    cat = category(client, ASHA, "buy-sell", "Cycles")
    listing = _listing(client, ASHA, cat)
    wanted = client.post(f"{API}/wanted", headers=ASHA, json={"title": "Need a cycle", "category_id": cat}).json()
    for value in ("NaN", "Infinity", "-Infinity"):
        r = _raw(client, "POST", "/listings", ASHA, f'{{"title": "Cycle", "price": {value}, "category_id": {cat}}}')
        assert r.status_code == 422, r.text
        assert r.json()["detail"][0]["loc"][-1] == "price"
        assert _raw(client, "PATCH", f"/listings/{listing['id']}", ASHA, f'{{"price": {value}}}').status_code == 422
        r = _raw(client, "POST", "/wanted", ASHA, f'{{"title": "Cycle", "max_price": {value}, "category_id": {cat}}}')
        assert r.status_code == 422, r.text
        assert _raw(client, "PATCH", f"/wanted/{wanted['id']}", ASHA, f'{{"max_price": {value}}}').status_code == 422


# ---------------------------------------------------------------- EDGE-02: no constraint names in errors
def test_database_errors_do_not_name_constraints(client):
    r = client.post(f"{API}/listings", headers=ASHA, json={"title": "Cycle", "price": "10", "category_id": 999999})
    assert r.status_code == 422
    assert r.json() == {"detail": "A referenced item does not exist."}


# ---------------------------------------------------------------- EDGE-03: single-line titles
def test_titles_and_category_names_must_be_one_line(client):
    cat = category(client, ASHA, "buy-sell", "Cycles")
    assert client.post(f"{API}/buy-sell/categories", headers=ASHA, json={"name": "Bikes\nand more"}).status_code == 422
    r = client.post(f"{API}/listings", headers=ASHA, json={"title": "Cycle\r\nFREE", "price": "1", "category_id": cat})
    assert r.status_code == 422
    listing = _listing(client, ASHA, cat, description="Line one\nLine two")   # descriptions may span lines
    assert client.patch(f"{API}/listings/{listing['id']}", headers=ASHA, json={"title": "A\nB"}).status_code == 422


# ---------------------------------------------------------------- API-01: lift suspension on nobody
def test_lifting_a_suspension_for_an_unknown_user_is_404(client):
    make_admin(client, ADMIN)
    r = client.post(f"{API}/users/00000000-0000-0000-0000-000000000001/lift-listing-suspension", headers=ADMIN)
    assert r.status_code == 404
    asha = sign_in(client, ASHA)
    assert client.post(f"{API}/users/{asha}/lift-listing-suspension", headers=ADMIN).status_code == 204


# ---------------------------------------------------------------- SEC-01: upload contents checked
def test_uploads_whose_contents_do_not_match_their_type_are_refused(client, s3):
    cat = category(client, ASHA, "buy-sell", "Cycles")
    html = b"<html><script>alert(1)</script></html>"
    fake = upload(client, s3, ASHA, "listing_photo", html, content_type="image/webp")
    r = client.post(f"{API}/listings", headers=ASHA, json={"title": "Cycle", "price": "1", "category_id": cat,
                                                           "photo_keys": [fake]})
    assert r.status_code == 422 and "don't match its type" in r.json()["detail"]
    assert s3.list_objects_v2(Bucket=BUCKET, Prefix=fake).get("KeyCount", 0) == 0   # deleted
    real = upload(client, s3, ASHA, "listing_photo", b"RIFF\x00\x00\x00\x00WEBPVP8 ", content_type="image/webp")
    assert client.post(f"{API}/listings", headers=ASHA, json={"title": "Cycle", "price": "1", "category_id": cat,
                                                              "photo_keys": [real]}).status_code == 201


# ---------------------------------------------------------------- DI-01: reports on posts deleted with a category
def test_deleting_a_category_with_its_posts_closes_out_their_reports(client):
    make_admin(client, ADMIN)
    sign_in(client, ASHA)
    ravi = sign_in(client, RAVI)
    bottle = category(client, ASHA, "buy-sell", "Bottle")
    listing = _listing(client, ASHA, bottle, "Steel bottle")
    assert client.post(f"{API}/reports", headers=RAVI, json={
        "target_type": "listing", "target_id": listing["id"], "reason": "fake"}).status_code == 201
    assert client.delete(f"{API}/buy-sell/categories/{bottle}?delete_posts=true", headers=ADMIN).status_code == 204
    log = sql("SELECT action, target_id, reason FROM moderation_log WHERE action = 'delete_reported_post_with_category'")
    assert [str(r["target_id"]) for r in log] == [listing["id"]] and "Steel bottle" in log[0]["reason"]
    told = [json.loads(r["payload"]) for r in sql(
        "SELECT payload FROM notifications WHERE user_id = $1::uuid", ravi)]
    assert any(p.get("kind") == "report_resolved" for p in told)


# ---------------------------------------------------------------- DI-02: removed Lost & Found photos are purged
def test_removing_a_lost_report_deletes_its_photos(client, s3):
    cat = category(client, ASHA, "lost-found", "Wallet")
    key = upload(client, s3, ASHA, "lost_report_photo", b"wallet")
    r = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "title": "Black wallet", "description": "Black leather wallet", "category_id": cat,
        "occurred_at": "2026-11-01T10:00:00Z", "location": "Library", "photo_keys": [key]})
    assert r.status_code == 201, r.text
    assert client.delete(f"{API}/lost-reports/{r.json()['id']}", headers=ASHA).status_code == 204
    assert sql("SELECT count(*) AS n FROM lost_report_photos")[0]["n"] == 0
    assert s3.list_objects_v2(Bucket=BUCKET, Prefix=key).get("KeyCount", 0) == 0


# ---------------------------------------------------------------- DI-03: bookmarks of deleted listings
def test_deleting_a_listing_removes_its_bookmarks(client):
    cat = category(client, ASHA, "buy-sell", "Cycles")
    listing = _listing(client, ASHA, cat)
    assert client.put(f"{API}/me/bookmarks/listing/{listing['id']}", headers=RAVI).status_code == 200
    assert client.delete(f"{API}/listings/{listing['id']}", headers=ASHA).status_code == 204
    assert sql("SELECT count(*) AS n FROM bookmarks WHERE target_id = $1::uuid", listing["id"])[0]["n"] == 0


# ---------------------------------------------------------------- FUNC-02: the admin's account list
def test_admin_lists_and_searches_accounts(client):
    make_admin(client, ADMIN)
    for who in (ASHA, RAVI, MEERA):
        sign_in(client, who)
    meera = sign_in(client, MEERA)
    sql("UPDATE users SET is_active = false WHERE id = $1::uuid", meera)
    assert client.get(f"{API}/users", headers=ASHA).status_code == 403
    grant(client, ADMIN, "ravi@iisc.ac.in", "buy_sell")
    assert client.get(f"{API}/users", headers=RAVI).status_code == 403   # moderators can't either

    page = client.get(f"{API}/users", headers=ADMIN).json()
    assert [u["email"] for u in page["items"]] == ["admin@iisc.ac.in", "asha@iisc.ac.in", "meera@iisc.ac.in",
                                                   "ravi@iisc.ac.in"]
    assert page["items"][0]["is_admin"] and not page["has_more"]
    assert [u["name"] for u in client.get(f"{API}/users?q=RAV", headers=ADMIN).json()["items"]] == ["Ravi"]
    off = client.get(f"{API}/users?status=deactivated", headers=ADMIN).json()["items"]
    assert [(u["email"], u["is_active"]) for u in off] == [("meera@iisc.ac.in", False)]
    assert client.get(f"{API}/users?limit=2", headers=ADMIN).json()["has_more"]


# ---------------------------------------------------------------- EDGE-06: earliest date for Lost & Found
def test_lost_and_found_dates_have_an_earliest_value(client):
    cat = category(client, ASHA, "lost-found", "Wallet")
    body = {"description": "Black leather wallet", "category_id": cat, "location": "Library"}
    r = client.post(f"{API}/lost-reports", headers=ASHA, json=body | {"occurred_at": "0026-11-01T10:00:00Z"})
    assert r.status_code == 422 and "before 2020" in r.text
    assert client.post(f"{API}/lost-reports", headers=ASHA,
                       json=body | {"occurred_at": "2026-11-01T10:00:00Z"}).status_code == 201


# ---------------------------------------------------------------- INFRA-02: CORS only for known origins
def test_cors_allows_local_dev_but_not_other_websites(client):
    def preflight(origin):
        return client.options(f"{API}/listings", headers={"Origin": origin, "Access-Control-Request-Method": "GET"})
    assert preflight("http://localhost:5000").headers.get("access-control-allow-origin") == "http://localhost:5000"
    evil = preflight("https://evil.example.com")
    assert "access-control-allow-origin" not in evil.headers


# ---------------------------------------------------------------- only owners edit Buy & Sell / Lost & Found posts
def test_admins_and_moderators_cannot_edit_other_peoples_posts(client):
    make_admin(client, ADMIN)
    sign_in(client, RAVI)
    grant(client, ADMIN, "ravi@iisc.ac.in", "buy_sell")
    grant(client, ADMIN, "ravi@iisc.ac.in", "lost_found")
    cat = category(client, ASHA, "buy-sell", "Cycles")
    listing = _listing(client, ASHA, cat)
    wanted = client.post(f"{API}/wanted", headers=ASHA, json={"title": "Need a cycle", "category_id": cat}).json()
    lf_cat = category(client, ASHA, "lost-found", "Wallet")
    report = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "description": "Black wallet", "category_id": lf_cat, "occurred_at": "2026-11-01T10:00:00Z",
        "location": "Library"}).json()
    for who in (ADMIN, RAVI):
        assert client.patch(f"{API}/listings/{listing['id']}", headers=who, json={"title": "x"}).status_code == 403
        assert client.patch(f"{API}/listings/{listing['id']}/status", headers=who,
                            json={"status": "sold"}).status_code == 403
        assert client.put(f"{API}/listings/{listing['id']}/photos", headers=who,
                          json={"photo_keys": []}).status_code == 403
        assert client.patch(f"{API}/wanted/{wanted['id']}", headers=who, json={"title": "x"}).status_code == 403
        assert client.patch(f"{API}/lost-reports/{report['id']}", headers=who,
                            json={"description": "x"}).status_code == 403
        assert client.patch(f"{API}/lost-reports/{report['id']}/status", headers=who,
                            json={"status": "closed"}).status_code == 403
    # The owner still can, and moderators can still remove the post.
    assert client.patch(f"{API}/listings/{listing['id']}", headers=ASHA, json={"title": "Bike"}).status_code == 200
    assert client.delete(f"{API}/listings/{listing['id']}", headers=RAVI).status_code == 204


def test_listing_cards_get_a_description_preview(client):
    cat = category(client, ASHA, "buy-sell", "Books")
    long = "Barely used. " * 40
    listing = _listing(client, ASHA, cat, description=long)
    card = client.get(f"{API}/listings").json()["items"][0]
    assert card["description"].startswith("Barely used.") and card["description"].endswith("…")
    assert len(card["description"]) <= 300
    assert client.get(f"{API}/listings/{listing['id']}").json()["description"] == long.strip()
