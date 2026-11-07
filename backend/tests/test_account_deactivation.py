"""Deactivating an account: the person's own button, what stays behind, and moderator grants."""
import pytest

from app import cognito_accounts
from app.cognito_accounts import AccountCheckUnavailable
from app.routers import moderators

from .conftest import ADMIN, API, ASHA, RAVI, category, grant, make_admin, sign_in, sql


def _listing(client, headers, title="Cycle"):
    cat = category(client, headers, "buy-sell", "Cycles")
    r = client.post(f"{API}/listings", headers=headers, json={"title": title, "price": "1000", "category_id": cat})
    assert r.status_code == 201, r.text
    return r.json()


def test_a_person_deactivates_their_own_account(client):
    make_admin(client, ADMIN)
    asha_id = sign_in(client, ASHA)
    sign_in(client, RAVI)
    grant(client, ADMIN, "asha@iisc.ac.in", "buy_sell")
    listing = _listing(client, ASHA)
    assert client.post(f"{API}/me/deactivate", headers=ADMIN).status_code == 422  # the admin must hand over first

    assert client.post(f"{API}/me/deactivate", headers=ASHA).status_code == 204
    # Asha can't sign in any more
    assert client.get(f"{API}/me", headers=ASHA).status_code == 403
    # the listing stays, and says its seller is deactivated
    seen = client.get(f"{API}/listings/{listing['id']}", headers=RAVI).json()
    assert seen["seller_deactivated"] is True and seen["seller"]["id"] == asha_id
    assert any(r["id"] == listing["id"] and r["seller_deactivated"] for r in
               client.get(f"{API}/listings", headers=RAVI).json()["items"])
    # her moderator role ended, so a stale role can't keep working
    assert [r["n"] for r in sql(
        "SELECT count(*) AS n FROM moderator_assignments WHERE user_id = $1::uuid AND revoked_at IS NULL",
        asha_id)] == [0]
    assert [r["n"] for r in sql(
        "SELECT count(*) AS n FROM moderation_log WHERE action = 'deactivate_user' AND target_id = $1::uuid",
        asha_id)] == [1]


def test_a_deactivated_account_can_reactivate_by_signing_in_again(client):
    sign_in(client, ASHA)
    assert client.post(f"{API}/me/deactivate", headers=ASHA).status_code == 204
    assert client.get(f"{API}/me", headers=ASHA).status_code == 403

    # /me still 403s -- reactivating is a separate, deliberate step, not automatic
    r = client.post(f"{API}/me/reactivate", headers=ASHA)
    assert r.status_code == 200 and r.json()["email"] == "asha@iisc.ac.in"
    assert client.get(f"{API}/me", headers=ASHA).status_code == 200

    asha_id = r.json()["id"]
    assert [r["n"] for r in sql(
        "SELECT count(*) AS n FROM moderation_log WHERE action = 'reactivate_user' AND target_id = $1::uuid",
        asha_id)] == [1]


def test_reactivating_an_already_active_account_is_a_no_op(client):
    sign_in(client, ASHA)
    r = client.post(f"{API}/me/reactivate", headers=ASHA)
    assert r.status_code == 200
    asha_id = r.json()["id"]
    assert [r["n"] for r in sql(
        "SELECT count(*) AS n FROM moderation_log WHERE action = 'reactivate_user' AND target_id = $1::uuid",
        asha_id)] == [0]


def test_active_listings_are_not_marked(client):
    sign_in(client, ASHA)
    listing = _listing(client, ASHA)
    assert client.get(f"{API}/listings/{listing['id']}", headers=RAVI).json()["seller_deactivated"] is False


def test_a_deactivated_account_cannot_get_a_moderator_role(client):
    make_admin(client, ADMIN)
    sign_in(client, RAVI)
    assert client.post(f"{API}/me/deactivate", headers=RAVI).status_code == 204
    r = grant(client, ADMIN, "ravi@iisc.ac.in", "buy_sell")
    assert r.status_code == 422 and "deactivated" in r.json()["detail"]


def test_a_role_is_refused_when_the_cognito_account_is_gone_but_granted_when_cognito_is_unreachable(client, monkeypatch):
    make_admin(client, ADMIN)
    sign_in(client, RAVI)

    async def gone(sub):
        return "This person's sign-in account no longer exists, so they can't use a moderator role."
    monkeypatch.setattr(moderators, "signin_account_problem", gone)
    r = grant(client, ADMIN, "ravi@iisc.ac.in", "buy_sell")
    assert r.status_code == 422 and "no longer exists" in r.json()["detail"]

    async def unreachable(sub):
        raise AccountCheckUnavailable("throttled")
    monkeypatch.setattr(moderators, "signin_account_problem", unreachable)
    assert grant(client, ADMIN, "ravi@iisc.ac.in", "buy_sell").status_code == 201


def test_the_cognito_check_reads_the_pool(monkeypatch):
    class Settings:
        auth_mode = "cognito"
        cognito_user_pool_id = "ap-south-1_test"
        cognito_region = "ap-south-1"

    monkeypatch.setattr(cognito_accounts, "get_settings", lambda: Settings())
    answers = {}
    monkeypatch.setattr(cognito_accounts, "_admin_get_user", lambda pool, region, sub: answers.get(sub))
    answers["gone"] = None
    answers["disabled"] = {"Enabled": False, "UserStatus": "CONFIRMED"}
    answers["fine"] = {"Enabled": True, "UserStatus": "CONFIRMED"}
    assert asyncio_run(cognito_accounts.signin_account_problem("gone")).startswith("This person's sign-in account no longer")
    assert "disabled" in asyncio_run(cognito_accounts.signin_account_problem("disabled"))
    assert asyncio_run(cognito_accounts.signin_account_problem("fine")) is None


def test_dev_sign_in_skips_the_cognito_check(monkeypatch):
    class Settings:
        auth_mode = "dev"

    monkeypatch.setattr(cognito_accounts, "get_settings", lambda: Settings())
    assert asyncio_run(cognito_accounts.signin_account_problem("dev|asha@iisc.ac.in")) is None


def asyncio_run(coro):
    import asyncio
    return asyncio.run(coro)
