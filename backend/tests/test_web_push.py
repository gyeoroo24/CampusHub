"""Web Push (FR-22): encryption a browser can decrypt, VAPID signatures, subscriptions and delivery."""
import io
import json
import urllib.error

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app import notify, webpush
from app.config import get_settings

from .conftest import ADMIN, API, ASHA, RAVI, make_admin, sign_in, sql


class Browser:
    """The receiving side of RFC 8291, as a browser does it."""

    def __init__(self):
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.public = self.key.public_key().public_bytes(serialization.Encoding.X962,
                                                         serialization.PublicFormat.UncompressedPoint)
        self.auth = b"0123456789abcdef"

    def subscription(self, endpoint="https://fcm.googleapis.com/fcm/send/abc123") -> str:
        return json.dumps({"endpoint": endpoint, "keys": {"p256dh": webpush.b64url(self.public),
                                                          "auth": webpush.b64url(self.auth)}})

    def decrypt(self, body: bytes) -> dict:
        salt, idlen = body[:16], body[20]
        as_public, ciphertext = body[21:21 + idlen], body[21 + idlen:]
        shared = self.key.exchange(ec.ECDH(), ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), as_public))
        ikm = webpush._hmac(webpush._hmac(self.auth, shared), b"WebPush: info\x00" + self.public + as_public + b"\x01")
        prk = webpush._hmac(salt, ikm)
        cek = webpush._hmac(prk, b"Content-Encoding: aes128gcm\x00\x01")[:16]
        nonce = webpush._hmac(prk, b"Content-Encoding: nonce\x00\x01")[:12]
        plain = AESGCM(cek).decrypt(nonce, ciphertext, None)
        assert plain.endswith(b"\x02")
        return json.loads(plain[:-1])


def _private_key() -> str:
    key = ec.generate_private_key(ec.SECP256R1())
    return webpush.b64url(key.private_numbers().private_value.to_bytes(32, "big"))


def test_a_browser_can_decrypt_the_message():
    browser = Browser()
    sub = webpush.parse_subscription(browser.subscription())
    body = webpush.encrypt(json.dumps({"title": "Hi"}).encode(), sub["p256dh"], sub["auth"])
    assert browser.decrypt(body) == {"title": "Hi"}


def test_vapid_signature_verifies_with_the_public_key():
    vapid = webpush.VapidKey(_private_key(), "mailto:a@iisc.ac.in")
    header = vapid.authorization("https://fcm.googleapis.com/fcm/send/x")
    token, key = header.removeprefix("vapid t=").split(", k=")
    assert key == vapid.public_key
    signed, signature = token.rsplit(".", 1)
    claims = json.loads(webpush.b64url_decode(signed.split(".")[1]))
    assert claims["aud"] == "https://fcm.googleapis.com" and claims["sub"] == "mailto:a@iisc.ac.in"
    raw = webpush.b64url_decode(signature)
    public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), webpush.b64url_decode(key))
    public.verify(encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big")),
                  signed.encode(), ec.ECDSA(hashes.SHA256()))   # raises if the signature is wrong


@pytest.mark.parametrize("endpoint", ["http://fcm.googleapis.com/x", "https://evil.example.com/push",
                                      "https://fcm.googleapis.com.evil.example.com/x", "https://169.254.169.254/"])
def test_subscriptions_must_point_at_a_browser_push_service(client, endpoint):
    body = {"platform": "web", "push_token": Browser().subscription(endpoint)}
    assert client.post(f"{API}/me/devices", headers=ASHA, json=body).status_code == 422
    body = {"platform": "web", "push_token": "not json"}
    assert client.post(f"{API}/me/devices", headers=ASHA, json=body).status_code == 422


@pytest.fixture
def push_on(monkeypatch):
    monkeypatch.setattr(get_settings(), "vapid_private_key", _private_key())
    monkeypatch.setattr(notify, "push_sender", None)   # pick the sender again from the settings
    yield
    notify.push_sender = None


def test_push_config(client, push_on, monkeypatch):
    r = client.get(f"{API}/me/push-config", headers=ASHA).json()
    assert r["enabled"] and r["public_key"] == webpush.public_key_of(get_settings().vapid_private_key)
    monkeypatch.setattr(get_settings(), "vapid_private_key", None)
    assert client.get(f"{API}/me/push-config", headers=ASHA).json() == {"enabled": False, "public_key": None}
    assert client.get(f"{API}/me/push-config").status_code == 401


def test_a_forum_reply_is_pushed_to_the_browser(client, push_on, monkeypatch):
    """A real alert path: the reply is in the inbox and arrives encrypted at the browser's push service."""
    browser = Browser()
    assert client.post(f"{API}/me/devices", headers=RAVI,
                       json={"platform": "web", "push_token": browser.subscription()}).status_code == 204
    sent = []

    class Ok(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    def fake_urlopen(request, timeout):
        sent.append(request)
        return Ok()
    monkeypatch.setattr(webpush.urllib.request, "urlopen", fake_urlopen)

    make_admin(client, ADMIN)
    cds = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CDS"}).json()
    course = client.post(f"{API}/departments/{cds['id']}/courses", headers=ADMIN,
                         json={"code": "DS 252", "name": "Cloud Computing"}).json()["id"]
    forum = client.get(f"{API}/courses/{course}/forum").json()
    thread = client.post(f"{API}/forums/{forum['id']}/threads", headers=RAVI,
                         json={"title": "Exam date?", "content": "When is it?"}).json()
    r = client.post(f"{API}/threads/{thread['id']}/comments", headers=ASHA, json={"content": "Next Monday"})
    assert r.status_code == 201, r.text

    assert len(sent) == 1
    request = sent[0]
    assert request.full_url == "https://fcm.googleapis.com/fcm/send/abc123"
    assert request.headers["Content-encoding"] == "aes128gcm"
    assert request.headers["Authorization"].startswith("vapid t=")
    message = browser.decrypt(request.data)
    assert message["title"] == "New reply" and message["tag"] == "forum_reply" and message["body"]


def test_gone_subscriptions_are_forgotten(client, push_on, monkeypatch):
    browser = Browser()
    user_id = sign_in(client, ASHA)
    client.post(f"{API}/me/devices", headers=ASHA, json={"platform": "web", "push_token": browser.subscription()})

    def gone(request, timeout):
        raise urllib.error.HTTPError(request.full_url, 410, "Gone", {}, None)
    monkeypatch.setattr(webpush.urllib.request, "urlopen", gone)
    from uuid import UUID
    client.portal.call(notify.deliver_push, [UUID(user_id)], "listing_watch", {"message": "Price dropped"})
    assert sql("SELECT 1 FROM push_devices") == []


def test_push_messages_open_the_right_page():
    assert notify.push_message("chat_message", {"conversation_id": "c1", "message": "m"})["url"] == "/messages/c1"
    assert notify.push_message("listing_watch", {"listing_id": "l1", "message": "m"})["url"] == "/buy/l1"
    assert notify.push_message("bookmarked_event_update", {"event_id": "e1"})["url"] == "/events/e1"
    assert notify.push_message("lost_found_match", {"message": "m"})["url"] == "/lost-found"


def test_the_sender_lambda_handler(monkeypatch):
    browser = Browser()
    monkeypatch.setattr(webpush, "_vapid", webpush.VapidKey(_private_key(), "mailto:a@iisc.ac.in"))
    bodies = []

    def fake_urlopen(request, timeout):
        bodies.append(request.data)
        raise urllib.error.HTTPError(request.full_url, 404, "Not Found", {}, None)
    monkeypatch.setattr(webpush.urllib.request, "urlopen", fake_urlopen)
    token = browser.subscription()
    assert webpush.lambda_handler({"tokens": [token], "message": {"title": "T"}}, None) == {"gone": [token]}
    assert browser.decrypt(bodies[0]) == {"title": "T"}
