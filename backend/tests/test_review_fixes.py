"""Regression tests for the fixes from the 23 Oct 2026 backend review (bug ids B-n)."""
import asyncio
import json
import time
import urllib.parse
from datetime import datetime, timedelta, timezone
from uuid import UUID

import asyncpg
import boto3
import jwt
import pytest
from botocore.exceptions import ClientError
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException
from starlette.requests import Request

from .conftest import (ADMIN, API, ASHA, BUCKET, DB_URL, KIRAN, MEERA, RAVI, category, grant, make_admin, sign_in,
                       sql, upload)


def _ago(**delta) -> str:
    return (datetime.now(timezone.utc) - timedelta(**delta)).isoformat()


@pytest.fixture
def campus(client):
    """CSA with E0 243 (Ravi is its course moderator) and CDS with DS 252."""
    make_admin(client, ADMIN)
    for h in (RAVI, ASHA, MEERA, KIRAN):
        sign_in(client, h)
    csa = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CSA"}).json()
    cds = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CDS"}).json()
    hpca = client.post(f"{API}/departments/{csa['id']}/courses", headers=ADMIN,
                       json={"code": "E0 243", "name": "HPCA"}).json()
    cloud = client.post(f"{API}/departments/{cds['id']}/courses", headers=ADMIN,
                        json={"code": "DS 252", "name": "Cloud Computing"}).json()
    assert grant(client, ADMIN, "ravi@iisc.ac.in", "academic_help", "course", course_id=hpca["id"]).status_code == 201
    return {"csa": csa, "hpca": hpca, "cloud": cloud}


def _listing(client, headers, title="Cycle", **extra):
    cat = category(client, headers, "buy-sell", "Cycles")
    r = client.post(f"{API}/listings", headers=headers, json={"title": title, "price": "1000", "category_id": cat, **extra})
    assert r.status_code == 201, r.text
    return r.json()


def _thread(client, headers, course_id, title="Doubt", content="How do caches work?"):
    forum = client.get(f"{API}/courses/{course_id}/forum").json()
    r = client.post(f"{API}/forums/{forum['id']}/threads", headers=headers, json={"title": title, "content": content})
    assert r.status_code == 201, r.text
    return r.json()


def _report(client, headers, target_type, target_id):
    r = client.post(f"{API}/reports", headers=headers,
                    json={"target_type": target_type, "target_id": target_id, "reason": "not allowed"})
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------- feedback rule (team decision on B-1)
def test_course_moderator_removes_feedback_in_own_course_only(client, campus):
    hpca, cloud = campus["hpca"]["id"], campus["cloud"]["id"]
    own = client.post(f"{API}/courses/{hpca}/feedback", headers=ASHA, json={"content": "Hard exams"}).json()
    other = client.post(f"{API}/courses/{cloud}/feedback", headers=ASHA, json={"content": "Great labs"}).json()
    assert client.patch(f"{API}/feedback/{own['id']}", headers=RAVI, json={"content": "x"}).status_code == 403
    assert client.delete(f"{API}/feedback/{other['id']}", headers=RAVI).status_code == 403
    assert client.delete(f"{API}/feedback/{own['id']}", headers=RAVI, params={"reason": "abusive"}).status_code == 204
    log = sql("SELECT action, reason FROM moderation_log WHERE target_id = $1::uuid", own["id"])
    assert [(r["action"], r["reason"]) for r in log] == [("remove_course_feedback", "abusive")]


# ---------------------------------------------------------------- sign-in (B-2, B-3, B-8, B-9, B-17, B-20)
@pytest.fixture
def cognito(monkeypatch):
    """Switch the running app to Cognito mode with a test signing key; returns a header factory."""
    from app import auth
    from app.config import get_settings
    s = get_settings()
    monkeypatch.setattr(s, "auth_mode", "cognito")
    monkeypatch.setattr(s, "cognito_user_pool_id", "ap-south-1_TEST")
    monkeypatch.setattr(s, "cognito_app_client_id", "client123")
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    class Jwks:
        def get_signing_key_from_jwt(self, token):
            return type("K", (), {"key": private.public_key()})()
    monkeypatch.setattr(auth, "_jwks_client", Jwks())
    issuer = "https://cognito-idp.ap-south-1.amazonaws.com/ap-south-1_TEST"

    def headers(sub="sub-1", email="asha@iisc.ac.in", **claims):
        now = int(time.time())
        body = {"sub": sub, "email": email, "email_verified": True, "aud": "client123", "iss": issuer,
                "token_use": "id", "iat": now, "exp": now + 3600, **claims}
        return {"Authorization": "Bearer " + jwt.encode(body, private, algorithm="RS256")}
    return headers


def test_unverified_email_cannot_create_an_account(client, cognito):
    r = client.get(f"{API}/me", headers=cognito(email="director@iisc.ac.in", email_verified=False))
    assert r.status_code == 403 and "code" in r.json()["detail"]
    assert sql("SELECT 1 FROM users") == []
    assert client.get(f"{API}/me", headers=cognito(email="director@iisc.ac.in")).status_code == 200


def test_recreated_cognito_account_is_relinked(client, cognito):
    first = client.get(f"{API}/me", headers=cognito(sub="old-sub")).json()
    again = client.get(f"{API}/me", headers=cognito(sub="new-sub"))
    assert again.status_code == 200 and again.json()["id"] == first["id"]


def test_bad_tokens_rejected_on_public_pages_too(client, cognito):
    assert client.get(f"{API}/listings").status_code == 200
    assert client.get(f"{API}/listings", headers={"Authorization": "Bearer garbage"}).status_code == 401
    expired = cognito(exp=int(time.time()) - 10)
    assert client.get(f"{API}/departments", headers=expired).status_code == 401


def test_unreachable_signing_keys_give_503(client, cognito, monkeypatch):
    from app import auth

    class Down:
        def get_signing_key_from_jwt(self, token):
            raise jwt.PyJWKClientConnectionError("timed out")
    monkeypatch.setattr(auth, "_jwks_client", Down())
    assert client.get(f"{API}/me", headers=cognito()).status_code == 503


def test_parallel_first_sign_in_creates_one_user(client):
    from app.auth import _create_user

    async def go():
        conns = [await asyncpg.connect(DB_URL) for _ in range(6)]
        try:
            return await asyncio.gather(*(_create_user(c, "race-sub", "race@iisc.ac.in", "Race") for c in conns))
        finally:
            for c in conns:
                await c.close()
    rows = asyncio.run(go())
    assert len({r["id"] for r in rows}) == 1


def test_dev_sign_in_only_from_this_machine():
    from app.auth import _dev_identity

    def request(host):
        return Request({"type": "http", "headers": [(b"x-dev-user", b"asha@iisc.ac.in")], "client": (host, 5000)})
    assert _dev_identity(request("127.0.0.1"))["email"] == "asha@iisc.ac.in"
    with pytest.raises(HTTPException) as exc:
        _dev_identity(request("203.0.113.9"))
    assert exc.value.status_code == 403


def test_dev_sign_in_from_the_network_needs_the_team_key(monkeypatch):
    from app.auth import _dev_identity
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "dev_auth_key", "team-secret")

    def request(host, key=None):
        headers = [(b"x-dev-user", b"asha@iisc.ac.in")] + ([(b"x-dev-key", key.encode())] if key else [])
        return Request({"type": "http", "headers": headers, "client": (host, 5000)})
    assert _dev_identity(request("10.217.1.5", "team-secret"))["email"] == "asha@iisc.ac.in"
    for denied in (request("10.217.1.5"), request("10.217.1.5", "wrong"), request("8.8.8.8", "team-secret")):
        with pytest.raises(HTTPException) as exc:
            _dev_identity(denied)
        assert exc.value.status_code == 403


def test_dev_mode_needs_an_explicit_opt_in(monkeypatch):
    from app.config import get_settings
    from app.main import _check_settings
    s = get_settings()
    monkeypatch.setattr(s, "allow_dev_auth", False)
    with pytest.raises(RuntimeError):
        _check_settings()
    monkeypatch.setattr(s, "allow_dev_auth", True)
    monkeypatch.setenv("AWS_LAMBDA_FUNCTION_NAME", "campushub-api")
    with pytest.raises(RuntimeError):
        _check_settings()
    monkeypatch.delenv("AWS_LAMBDA_FUNCTION_NAME")
    _check_settings()


@pytest.mark.parametrize("email", ["a@ııſc.ac.in", "a@K.iisc.ac.in", "a@iisc.ac.in\n",
                                   "@iisc.ac.in", "a@iisc.ac.in.evil.com"])
def test_lookalike_emails_rejected_everywhere(email):
    from app.auth import is_iisc_email
    from lambdas.cognito_pre_signup import handler
    assert not is_iisc_email(email)
    with pytest.raises(Exception, match="Only IISc"):
        handler({"request": {"userAttributes": {"email": email}}}, None)


def test_real_iisc_emails_accepted_everywhere():
    from app.auth import is_iisc_email
    from lambdas.cognito_pre_signup import handler
    for email in ("a@iisc.ac.in", "Old.Student@ALUM.IISC.AC.IN"):
        assert is_iisc_email(email)
        handler({"request": {"userAttributes": {"email": email}}}, None)


# ---------------------------------------------------------------- admin powers and accounts
def test_admin_edits_others_content_and_it_is_logged(client, campus):
    listing = _listing(client, ASHA)
    url = f"{API}/listings/{listing['id']}"
    assert client.patch(url, headers=RAVI, json={"title": "x"}).status_code == 403
    assert client.patch(url, headers=ADMIN, json={"title": "Cycle (edited)"}).status_code == 200
    assert client.patch(f"{url}/status", headers=ADMIN, json={"status": "sold"}).json()["status"] == "sold"
    assert client.patch(url, headers=ASHA, json={"title": None}).status_code == 422
    thread = _thread(client, ASHA, campus["hpca"]["id"])
    assert client.patch(f"{API}/threads/{thread['id']}", headers=ADMIN, json={"title": "Caches"}).status_code == 200
    comment_id = thread["comments"][0]["id"]
    assert client.patch(f"{API}/comments/{comment_id}", headers=ADMIN, json={"content": "[edited]"}).status_code == 200
    actions = {r["action"] for r in sql("SELECT action FROM moderation_log WHERE action NOT LIKE 'grant%'")}
    assert actions == {"edit_listing", "change_listing_status", "rename_thread", "edit_comment"}


def test_admin_deactivates_and_reactivates_accounts(client):
    admin_id = make_admin(client, ADMIN)
    asha_id = sign_in(client, ASHA)
    listing = _listing(client, ASHA)
    assert client.patch(f"{API}/users/{asha_id}", headers=RAVI, json={"is_active": False}).status_code == 403
    assert client.patch(f"{API}/users/{admin_id}", headers=ADMIN, json={"is_active": False}).status_code == 422
    r = client.patch(f"{API}/users/{asha_id}", headers=ADMIN, json={"is_active": False})
    assert r.status_code == 200 and r.json()["is_active"] is False
    assert client.get(f"{API}/listings", headers=ASHA).status_code == 403      # list pages too, not only details
    assert client.get(f"{API}/listings/{listing['id']}", headers=RAVI).json()["seller_contact"] is None
    r = client.patch(f"{API}/users/{asha_id}", headers=ADMIN, json={"is_active": True})
    assert r.json() | {"id": None} == {"id": None, "email": "asha@iisc.ac.in", "name": "Asha",
                                       "is_active": True, "is_admin": False}
    # admin changes only go through the hand-over endpoint
    assert client.patch(f"{API}/users/{asha_id}", headers=ADMIN, json={"is_admin": True}).status_code == 422


def test_admin_hands_over_the_role(client):
    admin_id = make_admin(client, ADMIN)
    asha_id, ravi_id = sign_in(client, ASHA), sign_in(client, RAVI)
    assert client.post(f"{API}/users/{ravi_id}/make-admin", headers=ASHA).status_code == 403   # not the admin
    assert client.post(f"{API}/users/{admin_id}/make-admin", headers=ADMIN).status_code == 422  # self
    r = client.post(f"{API}/users/{asha_id}/make-admin", headers=ADMIN)
    assert r.status_code == 200 and r.json()["is_admin"] is True
    assert client.get(f"{API}/me", headers=ADMIN).json()["is_admin"] is False   # downgraded
    assert client.get(f"{API}/me", headers=ASHA).json()["is_admin"] is True
    assert [r["n"] for r in sql("SELECT count(*) AS n FROM users WHERE base_role = 'admin'")] == [1]
    # the old admin can't do it any more; the new one can pass it on
    assert client.post(f"{API}/users/{ravi_id}/make-admin", headers=ADMIN).status_code == 403
    client.patch(f"{API}/users/{ravi_id}", headers=ASHA, json={"is_active": False})
    assert client.post(f"{API}/users/{ravi_id}/make-admin", headers=ASHA).status_code == 422   # deactivated
    with pytest.raises(asyncpg.UniqueViolationError):   # the database itself allows one admin
        sql("UPDATE users SET base_role = 'admin' WHERE id = $1::uuid", ravi_id)


# ---------------------------------------------------------------- moderation (B-5, B-12, B-13)
def test_removing_content_closes_its_reports(client, campus):
    grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell")
    listing = _listing(client, ASHA)
    _report(client, RAVI, "listing", listing["id"])
    assert client.delete(f"{API}/listings/{listing['id']}", headers=MEERA, params={"reason": "spam"}).status_code == 204
    rows = sql("SELECT status::text AS s, resolution_note FROM reports WHERE listing_id = $1::uuid", listing["id"])
    assert [(r["s"], r["resolution_note"]) for r in rows] == [("actioned", "spam")]
    # removing a thread also closes reports about its comments
    thread = _thread(client, ASHA, campus["hpca"]["id"])
    reply = client.post(f"{API}/threads/{thread['id']}/comments", headers=KIRAN, json={"content": "buy followers"}).json()
    _report(client, MEERA, "comment", reply["id"])
    assert client.delete(f"{API}/threads/{thread['id']}", headers=ASHA).status_code == 204
    assert sql("SELECT status::text AS s FROM reports WHERE comment_id = $1::uuid", reply["id"])[0]["s"] == "actioned"


def test_concurrent_resolution_doesnt_remove_dismissed_content(client):
    admin_id = make_admin(client, ADMIN)
    sign_in(client, MEERA)
    grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell")
    listing = _listing(client, ASHA)
    report = _report(client, RAVI, "listing", listing["id"])

    async def scenario():
        other = await asyncpg.connect(DB_URL)          # another moderator, mid-way through dismissing it
        tx = other.transaction()
        await tx.start()
        await other.execute("SELECT 1 FROM reports WHERE id = $1::uuid FOR UPDATE", report["id"])
        resolving = asyncio.get_running_loop().run_in_executor(None, lambda: client.post(
            f"{API}/reports/{report['id']}/resolve", headers=MEERA, json={"action": "actioned", "remove_content": True}))
        await asyncio.sleep(1)
        await other.execute("UPDATE reports SET status = 'dismissed', handled_by = $2::uuid, handled_at = now() "
                            "WHERE id = $1::uuid", report["id"], admin_id)
        await tx.commit()
        await other.close()
        return await resolving
    assert asyncio.run(scenario()).status_code == 409
    assert client.get(f"{API}/listings/{listing['id']}").status_code == 200


def test_revoking_twice(client):
    make_admin(client, ADMIN)
    sign_in(client, MEERA)
    g = grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell").json()
    assert client.delete(f"{API}/moderators/{g['id']}", headers=ADMIN).status_code == 204
    assert client.delete(f"{API}/moderators/{g['id']}", headers=ADMIN).status_code == 404
    assert len(sql("SELECT 1 FROM moderation_log WHERE action = 'revoke_moderator'")) == 1


# ---------------------------------------------------------------- validation and search (B-11, B-14 to B-16, B-22)
def test_blank_text_is_rejected(client, campus):
    hpca = campus["hpca"]["id"]
    assert client.post(f"{API}/courses/{hpca}/feedback", headers=ASHA, json={"content": "   "}).status_code == 422
    assert client.post(f"{API}/departments/{campus['csa']['id']}/courses", headers=ADMIN,
                       json={"code": "  ", "name": "  "}).status_code == 422
    forum = client.get(f"{API}/courses/{hpca}/forum").json()
    assert client.post(f"{API}/forums/{forum['id']}/threads", headers=ASHA,
                       json={"title": " ", "content": "x"}).status_code == 422
    assert client.patch(f"{API}/me", headers=ASHA, json={"name": "   "}).status_code == 422
    r = client.post(f"{API}/courses/{hpca}/feedback", headers=ASHA, json={"content": "  Good course \n"})
    assert r.json()["content"] == "Good course"


def test_search_edge_cases(client):
    lf = category(client, ASHA, "lost-found", "Umbrella")
    for text in ("Blue umbrella", "Black wallet"):
        client.post(f"{API}/lost-reports", headers=ASHA,
                    json={"description": text, "category_id": lf, "occurred_at": _ago(hours=2)})
    count = lambda q: len(client.get(f"{API}/lost-reports", params={"q": q}).json()["items"])  # noqa: E731
    assert (count("%"), count("_"), count("e_u"), count("umbrella"), count("")) == (0, 0, 0, 1, 2)
    _listing(client, ASHA, "Hero cycle")
    _listing(client, ASHA, "Study lamp")
    listings = lambda q: len(client.get(f"{API}/listings", params={"q": q}).json()["items"])  # noqa: E731
    assert (listings(""), listings("the"), listings("cycle")) == (2, 2, 1)


def test_huge_ids_are_422_not_500(client):
    assert client.get(f"{API}/listings", params={"category_id": 99_999_999_999}).status_code == 422
    assert client.get(f"{API}/lost-reports", params={"category_id": 99_999_999_999}).status_code == 422
    r = client.post(f"{API}/listings", headers=ASHA, json={"title": "x", "price": "1", "category_id": 2 ** 40})
    assert r.status_code == 422


def test_one_file_backs_one_material(client, s3, campus):
    hpca = campus["hpca"]["id"]
    key = upload(client, s3, RAVI, "course_material", b"%PDF-1.4", "application/pdf", course_id=hpca)
    body = {"title": "Notes", "s3_key": key}
    assert client.post(f"{API}/courses/{hpca}/materials", headers=RAVI, json=body).status_code == 201
    assert client.post(f"{API}/courses/{hpca}/materials", headers=RAVI, json=body).status_code == 409


# ---------------------------------------------------------------- forums and matching (B-24, B-26)
def test_reading_a_forum_writes_only_once(client, campus):
    hpca = campus["hpca"]["id"]
    first = client.get(f"{API}/courses/{hpca}/forum").json()
    assert client.get(f"{API}/courses/{hpca}/forum").json()["id"] == first["id"]
    assert len(sql("SELECT 1 FROM forums")) == 1
    assert client.get(f"{API}/courses/00000000-0000-0000-0000-000000000000/forum").status_code == 404


def test_editing_a_found_report_reruns_matching_once(client):
    id_card = category(client, RAVI, "lost-found", "ID card")
    wallet = category(client, RAVI, "lost-found", "Wallet")
    client.post(f"{API}/lost-reports", headers=RAVI,
                json={"description": "Blue ID card", "category_id": id_card, "occurred_at": _ago(hours=3)})
    found = client.post(f"{API}/found-reports", headers=KIRAN,
                        json={"description": "A card", "category_id": wallet, "occurred_at": _ago(hours=1)}).json()
    matches = lambda: [n for n in client.get(f"{API}/me/notifications", headers=RAVI).json()["items"]  # noqa: E731
                       if n["type"] == "lost_found_match"]
    assert matches() == []
    url = f"{API}/found-reports/{found['id']}"
    assert client.patch(url, headers=KIRAN, json={"category_id": id_card}).status_code == 200
    assert len(matches()) == 1
    client.patch(url, headers=KIRAN, json={"description": "A blue card"})
    client.patch(f"{url}/status", headers=KIRAN, json={"status": "closed"})
    client.patch(f"{url}/status", headers=KIRAN, json={"status": "open"})
    assert len(matches()) == 1


# ---------------------------------------------------------------- uploads and files (B-4, B-7, B-10)
def test_attached_files_are_retagged(client, s3):
    key = upload(client, s3, ASHA, "listing_photo")
    _listing(client, ASHA, photo_keys=[key])
    assert s3.get_object_tagging(Bucket=BUCKET, Key=key)["TagSet"] == [{"Key": "state", "Value": "attached"}]


def test_file_failing_checks_is_deleted(client, s3):
    key = upload(client, s3, ASHA, "listing_photo")
    # Pretend a PDF got stored under that photo key (S3 itself would refuse this with the signed headers).
    s3.put_object(Bucket=BUCKET, Key=key, Body=b"%PDF", ContentType="application/pdf")
    cat = category(client, ASHA, "buy-sell", "Cycles")
    r = client.post(f"{API}/listings", headers=ASHA,
                    json={"title": "Cycle", "price": "1", "category_id": cat, "photo_keys": [key]})
    assert r.status_code == 422
    with pytest.raises(ClientError):
        s3.head_object(Bucket=BUCKET, Key=key)


def test_s3_403_for_missing_file_is_422(client, monkeypatch):
    from app.storage import s3_client
    asha_id = sign_in(client, ASHA)

    def denied(**kwargs):
        raise ClientError({"Error": {"Code": "403", "Message": "Forbidden"}}, "HeadObject")
    monkeypatch.setattr(s3_client(), "head_object", denied)
    cat = category(client, ASHA, "buy-sell", "Cycles")
    r = client.post(f"{API}/listings", headers=ASHA, json={
        "title": "Cycle", "price": "1", "category_id": cat, "photo_keys": [f"listings/{asha_id}/never-uploaded.jpg"]})
    assert r.status_code == 422


def test_cdn_links_are_signed_and_expire(monkeypatch):
    from app import storage
    from app.config import get_settings
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    s = get_settings()
    monkeypatch.setattr(s, "cdn_base_url", "https://d123.cloudfront.net/")
    monkeypatch.setattr(s, "cdn_key_pair_id", "K2TESTKEY")
    monkeypatch.setattr(s, "cdn_private_key", pem)
    storage._cdn_signer.cache_clear()
    try:
        url = storage.file_url("listings/u/photo 1.jpg")
    finally:
        storage._cdn_signer.cache_clear()
    query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
    assert url.startswith("https://d123.cloudfront.net/listings/u/photo%201.jpg?")
    assert query["Key-Pair-Id"] == ["K2TESTKEY"] and "Signature" in query
    assert time.time() < int(query["Expires"][0]) <= time.time() + s.download_url_expiry_seconds + 5


# ---------------------------------------------------------------- notifications, jobs and config
def test_unregister_device_with_token_in_body(client):
    body = {"platform": "android", "push_token": "fcm-token-123"}
    assert client.post(f"{API}/me/devices", headers=ASHA, json=body).status_code == 204
    r = client.request("DELETE", f"{API}/me/devices", headers=ASHA, json={"push_token": "fcm-token-123"})
    assert r.status_code == 204 and sql("SELECT 1 FROM push_devices") == []


def test_slow_push_is_cut_off(client, monkeypatch):
    from app import notify
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "push_timeout_seconds", 0.2)

    class Slow:
        async def send(self, devices, notification_type, payload):
            await asyncio.sleep(5)
    monkeypatch.setattr(notify, "push_sender", Slow())
    user_id = UUID(sign_in(client, ASHA))
    started = time.time()
    client.portal.call(notify.deliver_push, [user_id], "forum_reply", {"message": "hi"})
    assert time.time() - started < 2


def test_purge_deletes_only_old_notifications(client):
    from app.jobs import purge_notifications
    user_id = sign_in(client, ASHA)
    sql("""INSERT INTO notifications (user_id, type, payload, created_at) VALUES
           ($1::uuid, 'forum_reply', '{}', now() - interval '31 days'), ($1::uuid, 'forum_reply', '{}', now())""",
        user_id)
    assert client.portal.call(purge_notifications) == 1
    assert len(sql("SELECT 1 FROM notifications")) == 1


def test_database_password_from_secrets_manager(s3):
    from app import db
    arn = boto3.client("secretsmanager", region_name="ap-south-1").create_secret(
        Name="campushub/db", SecretString=json.dumps({"username": "app", "password": "s3cret"}))["ARN"]
    db._credentials = None
    try:
        assert db._secret_credentials(arn) == {"user": "app", "password": "s3cret"}
    finally:
        db._credentials = None


def test_swagger_has_a_sign_in_button(client):
    schema = client.get("/openapi.json").json()
    assert schema["components"]["securitySchemes"]["signIn"]["name"] == "X-Dev-User"
    assert schema["security"] == [{"signIn": []}, {}]


def test_lambda_defaults(monkeypatch):
    from app.config import Settings
    monkeypatch.setenv("AWS_LAMBDA_FUNCTION_NAME", "campushub-api")
    inside = Settings()
    assert (inside.db_pool_max_size, inside.docs_enabled) == (2, False)
    monkeypatch.delenv("AWS_LAMBDA_FUNCTION_NAME")
    outside = Settings()
    assert (outside.db_pool_max_size, outside.docs_enabled) == (20, True)
