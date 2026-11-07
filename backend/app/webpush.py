"""Web Push (FR-22): send a notification to a browser's push subscription.

A browser that turns on notifications gives the app a subscription: an endpoint URL at its push service
(Google FCM for Chrome/Edge, Mozilla for Firefox, Apple for Safari) and two keys. To push, the server
encrypts the message for that browser (RFC 8291, aes128gcm) and POSTs it to the endpoint, signed with
the app's VAPID key (RFC 8292) so the push service knows who is sending. Only `cryptography` and the
standard library are used, so this also runs as the push-sender Lambda (lambda_handler below).

The API's own Lambdas run in a VPC without internet access, so in AWS they hand the work to the
push-sender Lambda, which runs outside the VPC (app/notify.py). Locally the API sends directly.

VAPID keys: the private key is the P-256 scalar and the public key the uncompressed point, both
base64url without padding (the format browsers and `npx web-push generate-vapid-keys` use).
"""
import base64
import json
import logging
import os
import struct
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlsplit

from cryptography.hazmat.primitives import hashes, hmac, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

log = logging.getLogger("campushub.webpush")

# Push services browsers use. A subscription pointing anywhere else is refused, so the server can't be
# made to POST to an arbitrary address.
PUSH_HOSTS = ("fcm.googleapis.com", "updates.push.services.mozilla.com", "push.services.mozilla.com",
              "web.push.apple.com", "notify.windows.com")
TTL_SECONDS = 24 * 3600
TIMEOUT_SECONDS = 5


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def b64url_decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


class InvalidSubscription(ValueError):
    pass


def parse_subscription(token: str) -> dict:
    """The JSON a browser's PushSubscription.toJSON() gives: {"endpoint", "keys": {"p256dh", "auth"}}."""
    try:
        sub = json.loads(token)
        endpoint, keys = sub["endpoint"], sub["keys"]
        p256dh, auth = b64url_decode(keys["p256dh"]), b64url_decode(keys["auth"])
    except (ValueError, KeyError, TypeError) as exc:
        raise InvalidSubscription("Not a Web Push subscription.") from exc
    parts = urlsplit(endpoint)
    host = (parts.hostname or "").lower()
    if parts.scheme != "https" or not any(host == h or host.endswith("." + h) for h in PUSH_HOSTS):
        raise InvalidSubscription("The subscription's endpoint isn't a known browser push service.")
    if len(p256dh) != 65 or p256dh[0] != 4 or len(auth) != 16:
        raise InvalidSubscription("The subscription's keys are malformed.")
    return {"endpoint": endpoint, "p256dh": p256dh, "auth": auth}


def _hmac(key: bytes, data: bytes) -> bytes:
    h = hmac.HMAC(key, hashes.SHA256())
    h.update(data)
    return h.finalize()


def encrypt(plaintext: bytes, p256dh: bytes, auth: bytes) -> bytes:
    """RFC 8291 message encryption with the aes128gcm content coding (RFC 8188), one record."""
    ua_public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), p256dh)
    as_private = ec.generate_private_key(ec.SECP256R1())
    as_public = as_private.public_key().public_bytes(serialization.Encoding.X962,
                                                    serialization.PublicFormat.UncompressedPoint)
    shared = as_private.exchange(ec.ECDH(), ua_public)
    ikm = _hmac(_hmac(auth, shared), b"WebPush: info\x00" + p256dh + as_public + b"\x01")
    salt = os.urandom(16)
    prk = _hmac(salt, ikm)
    cek = _hmac(prk, b"Content-Encoding: aes128gcm\x00\x01")[:16]
    nonce = _hmac(prk, b"Content-Encoding: nonce\x00\x01")[:12]
    record_size = 4096
    ciphertext = AESGCM(cek).encrypt(nonce, plaintext + b"\x02", None)   # 0x02: last (only) record
    return salt + struct.pack("!IB", record_size, len(as_public)) + as_public + ciphertext


class VapidKey:
    def __init__(self, private_key_b64: str, subject: str):
        scalar = int.from_bytes(b64url_decode(private_key_b64.strip()), "big")
        self._key = ec.derive_private_key(scalar, ec.SECP256R1())
        self.public_key = b64url(self._key.public_key().public_bytes(
            serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint))
        self.subject = subject

    def authorization(self, endpoint: str) -> str:
        parts = urlsplit(endpoint)
        header = b64url(json.dumps({"typ": "JWT", "alg": "ES256"}).encode())
        claims = b64url(json.dumps({"aud": f"{parts.scheme}://{parts.netloc}",
                                    "exp": int(time.time()) + 12 * 3600, "sub": self.subject}).encode())
        r, s = decode_dss_signature(self._key.sign(f"{header}.{claims}".encode(), ec.ECDSA(hashes.SHA256())))
        signature = b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
        return f"vapid t={header}.{claims}.{signature}, k={self.public_key}"


def public_key_of(private_key_b64: str) -> str:
    return VapidKey(private_key_b64, "").public_key


def send_one(vapid: VapidKey, token: str, message: dict) -> bool:
    """Push one message. Returns False when the subscription is gone (unsubscribed or expired), so the
    caller can forget it; True otherwise (including transient failures, which are only logged)."""
    try:
        sub = parse_subscription(token)
    except InvalidSubscription:
        return False
    body = encrypt(json.dumps(message).encode(), sub["p256dh"], sub["auth"])
    request = urllib.request.Request(sub["endpoint"], data=body, method="POST", headers={
        "Authorization": vapid.authorization(sub["endpoint"]),
        "Content-Encoding": "aes128gcm",
        "Content-Type": "application/octet-stream",
        "TTL": str(TTL_SECONDS),
        "Urgency": "normal",
    })
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS):
            return True
    except urllib.error.HTTPError as exc:
        if exc.code in (404, 410):
            return False
        log.warning("Push service answered %s for %s", exc.code, urlsplit(sub["endpoint"]).hostname)
    except OSError as exc:
        log.warning("Couldn't reach %s: %s", urlsplit(sub["endpoint"]).hostname, exc)
    return True


def send_all(vapid: VapidKey, tokens: list[str], message: dict) -> list[str]:
    """Push to every token in parallel. Returns the tokens that are gone."""
    if not tokens:
        return []
    with ThreadPoolExecutor(max_workers=min(16, len(tokens))) as pool:
        alive = list(pool.map(lambda t: send_one(vapid, t, message), tokens))
    return [t for t, ok in zip(tokens, alive) if not ok]


# ---------------------------------------------------------------- the push-sender Lambda
_vapid: VapidKey | None = None


def _load_vapid() -> VapidKey:
    """The private key comes from SSM (a SecureString), read once per container."""
    global _vapid
    if _vapid is None:
        import boto3   # only in the Lambda; the API passes its own key to send_all
        name = os.environ["VAPID_PRIVATE_KEY_PARAMETER"]
        value = boto3.client("ssm").get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
        _vapid = VapidKey(value, os.environ.get("VAPID_SUBJECT", "mailto:admin@campushub.local"))
    return _vapid


def lambda_handler(event, _context):
    """{"tokens": [...], "message": {...}} -> {"gone": [tokens to forget]}"""
    return {"gone": send_all(_load_vapid(), list(event.get("tokens", [])), dict(event.get("message", {})))}
