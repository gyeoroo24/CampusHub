import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException

from .conftest import API, ASHA, RAVI, as_user, sign_in


def test_health(client):
    assert client.get(f"{API}/health").json() == {"status": "ok"}


def test_guest_cannot_see_me(client):
    assert client.get(f"{API}/me").status_code == 401


def test_first_request_creates_user_and_profile_update(client):
    me = client.get(f"{API}/me", headers=ASHA).json()
    assert me["email"] == "asha@iisc.ac.in" and me["is_admin"] is False and me["moderator_grants"] == []
    r = client.patch(f"{API}/me", headers=ASHA, json={"phone": "+919876543210", "programme": "M.Tech CSA"})
    assert r.status_code == 200 and r.json()["phone"] == "+919876543210"
    assert client.patch(f"{API}/me", headers=ASHA, json={"phone": "call me"}).status_code == 422
    assert client.patch(f"{API}/me", headers=ASHA, json={"name": None}).status_code == 422


@pytest.mark.parametrize("email", ["someone@gmail.com", "x@fakeiisc.ac.in"])
def test_non_iisc_email_rejected(client, email):
    assert client.get(f"{API}/me", headers=as_user(email)).status_code == 403


def test_alumni_subdomain_accepted(client):
    assert client.get(f"{API}/me", headers=as_user("Old.Student@ALUM.IISC.AC.IN")).status_code == 200


def test_contact_details_only_for_signed_in_users(client):
    asha_id = sign_in(client, ASHA)
    client.patch(f"{API}/me", headers=ASHA, json={"phone": "+919876543210"})
    assert client.get(f"{API}/users/{asha_id}").json()["contact"] is None
    contact = client.get(f"{API}/users/{asha_id}", headers=RAVI).json()["contact"]
    assert contact == {"email": "asha@iisc.ac.in", "phone": "+919876543210"}


# ---- Cognito ID-token verification (the production auth path) ----
class _FakeJwks:
    def __init__(self, public_key):
        self._key = public_key

    def get_signing_key_from_jwt(self, token):
        return type("K", (), {"key": self._key})()


@pytest.fixture
def cognito(monkeypatch):
    from app import auth
    from app.config import get_settings
    settings = get_settings()
    monkeypatch.setattr(settings, "cognito_user_pool_id", "ap-south-1_TEST")
    monkeypatch.setattr(settings, "cognito_app_client_id", "client123")
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    monkeypatch.setattr(auth, "_jwks_client", _FakeJwks(private.public_key()))
    issuer = "https://cognito-idp.ap-south-1.amazonaws.com/ap-south-1_TEST"

    def make(**overrides):
        now = int(time.time())
        claims = {"sub": "abc-123", "email": "asha@iisc.ac.in", "aud": "client123", "iss": issuer,
                  "token_use": "id", "iat": now, "exp": now + 3600, **overrides}
        return jwt.encode(claims, private, algorithm="RS256")
    return make


def test_valid_cognito_id_token(cognito):
    from app.auth import verify_cognito_id_token
    assert verify_cognito_id_token(cognito())["email"] == "asha@iisc.ac.in"


@pytest.mark.parametrize("override", [{"aud": "someone-else"}, {"token_use": "access"},
                                      {"exp": int(time.time()) - 10}, {"iss": "https://evil.example"}])
def test_bad_cognito_tokens_rejected(cognito, override):
    from app.auth import verify_cognito_id_token
    with pytest.raises(HTTPException) as exc:
        verify_cognito_id_token(cognito(**override))
    assert exc.value.status_code == 401
