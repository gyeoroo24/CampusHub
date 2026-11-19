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
    r = client.patch(f"{API}/me", headers=ASHA, json={"programme": "M.Tech CSA"})
    assert r.status_code == 200 and r.json()["programme"] == "M.Tech CSA"
    assert client.patch(f"{API}/me", headers=ASHA, json={"name": None}).status_code == 422


def test_phone_is_added_only_after_verifying_a_code(client, monkeypatch):
    # The code is random; pin it so the test knows what was "texted".
    monkeypatch.setattr("app.otp.secrets.randbelow", lambda _n: 123456)
    sign_in(client, ASHA)
    # A number can't be set directly, only removed.
    assert client.patch(f"{API}/me", headers=ASHA, json={"phone": "+919876543210"}).status_code == 422
    for bad in ("9876543210", "call me", "+91987654321", "+915876543210", "+0123456789"):
        assert client.post(f"{API}/me/phone/code", headers=ASHA, json={"phone": bad}).status_code == 422, bad
    assert client.post(f"{API}/me/phone/code", json={"phone": "+919876543210"}).status_code == 401

    assert client.post(f"{API}/me/phone/code", headers=ASHA, json={"phone": "+919876543210"}).status_code == 204
    wrong = client.post(f"{API}/me/phone/verify", headers=ASHA, json={"phone": "+919876543210", "code": "000000"})
    assert wrong.status_code == 401 and client.get(f"{API}/me", headers=ASHA).json()["phone"] is None
    r = client.post(f"{API}/me/phone/verify", headers=ASHA, json={"phone": "+919876543210", "code": "123456"})
    assert r.status_code == 200 and r.json()["phone"] == "+919876543210"
    # Other countries just need a valid international number.
    client.post(f"{API}/me/phone/code", headers=RAVI, json={"phone": "+14155550123"})
    assert client.post(f"{API}/me/phone/verify", headers=RAVI,
                       json={"phone": "+14155550123", "code": "123456"}).json()["phone"] == "+14155550123"

    assert client.patch(f"{API}/me", headers=ASHA, json={"phone": None}).json()["phone"] is None


@pytest.mark.parametrize("email", ["someone@gmail.com", "x@fakeiisc.ac.in"])
def test_non_iisc_email_rejected(client, email):
    assert client.get(f"{API}/me", headers=as_user(email)).status_code == 403


def test_alumni_subdomain_accepted(client):
    assert client.get(f"{API}/me", headers=as_user("Old.Student@ALUM.IISC.AC.IN")).status_code == 200


def test_contact_details_only_for_signed_in_users(client, monkeypatch):
    monkeypatch.setattr("app.otp.secrets.randbelow", lambda _n: 123456)   # the texted code
    asha_id = sign_in(client, ASHA)
    client.post(f"{API}/me/phone/code", headers=ASHA, json={"phone": "+919876543210"})
    client.post(f"{API}/me/phone/verify", headers=ASHA, json={"phone": "+919876543210", "code": "123456"})
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


def test_unknown_key_ids_dont_refetch_cognito_keys_every_request(monkeypatch):
    """Tokens with made-up key ids (no valid signature needed) must not each re-download Cognito's keys.

    Uses the real PyJWKClient; only the HTTP request for the key set is replaced, and counted.
    """
    import io
    import json
    import urllib.request

    from app import auth
    from app.config import get_settings
    settings = get_settings()
    monkeypatch.setattr(settings, "cognito_user_pool_id", "ap-south-1_TEST")
    monkeypatch.setattr(settings, "cognito_app_client_id", "client123")
    monkeypatch.setattr(auth, "_jwks_client", None)       # build a fresh real client
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = jwt.algorithms.RSAAlgorithm.to_jwk(private.public_key(), as_dict=True) | {
        "kid": "real", "alg": "RS256", "use": "sig"}
    fetches = []
    monkeypatch.setattr(urllib.request.OpenerDirector, "open", lambda self, request, *a, **kw:
                        fetches.append(1) or io.BytesIO(json.dumps({"keys": [jwk]}).encode()))
    now = int(time.time())
    claims = {"sub": "abc-123", "email": "asha@iisc.ac.in", "aud": "client123", "token_use": "id",
              "iss": "https://cognito-idp.ap-south-1.amazonaws.com/ap-south-1_TEST", "iat": now, "exp": now + 3600}

    def token(kid):
        return jwt.encode(claims, private, algorithm="RS256", headers={"kid": kid})

    def rejected(kid):
        with pytest.raises(HTTPException) as exc:
            auth.verify_cognito_id_token(token(kid))
        return exc.value.status_code == 401

    for _ in range(5):                                    # valid key id: fetched once, then cached
        assert auth.verify_cognito_id_token(token("real"))["sub"] == "abc-123"
    assert all(rejected(f"made-up-{i}") for i in range(10))    # 10 different unknown key ids
    assert all(rejected("made-up") for _ in range(10))         # the same unknown key id, 10 times
    assert len(fetches) == 1

    # A real key rotation is still picked up: after the cooldown, one unknown key id refreshes once.
    auth._jwks_client._last_successful_fetch -= auth._jwks_client.cooldown_duration + 1
    assert all(rejected("made-up") for _ in range(10))
    assert len(fetches) == 2


@pytest.mark.parametrize("override", [{"aud": "someone-else"}, {"token_use": "access"},
                                      {"exp": int(time.time()) - 10}, {"iss": "https://evil.example"}])
def test_bad_cognito_tokens_rejected(cognito, override):
    from app.auth import verify_cognito_id_token
    with pytest.raises(HTTPException) as exc:
        verify_cognito_id_token(cognito(**override))
    assert exc.value.status_code == 401
