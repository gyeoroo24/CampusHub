"""Reference implementation of the CampusHub messaging encryption (protocol "campushub-chat-v1").

The Flutter app (lib/features/messages/crypto/chat_crypto.dart) does the same thing; the tests use
this module to act as a real client, so they check that what the API stores and returns can be
decrypted only with the right keys. The server itself never runs any of this.

  identity key    X25519 key pair per user; the public half is uploaded (PUT /me/chat-key)
  key backup      private key, AES-256-GCM encrypted under PBKDF2-SHA256(passphrase, salt, iterations);
                  stored as nonce(12) || ciphertext || tag(16), AAD = "campushub-chat-key-backup-v1|<user id>"
  conversation    AES-256 key = HKDF-SHA256(X25519(mine, theirs), salt = "campushub-chat-v1",
                  info = "campushub-chat-v1|conv=<conversation id>|" || lower public key || higher public key)
  message         AES-256-GCM, random 12-byte nonce, plaintext = UTF-8 JSON
                  ({"v": 1, "type": "text", "text": ...} or {"v": 1, "type": "offer", "amount": "2400", "note": ...}),
                  AAD = "campushub-chat-v1|<conversation id>|<message id>|<sender id>|<kind>"
  safety number   SHA-512("campushub-safety-v1" || uid_a || pub_a || uid_b || pub_b), users sorted by id;
                  twelve groups of five digits, the same on both phones
"""
import base64
import hashlib
import json
import os
import uuid
from dataclasses import dataclass

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

PROTOCOL = "campushub-chat-v1"
BACKUP_AAD = "campushub-chat-key-backup-v1"


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def unb64(text: str) -> bytes:
    return base64.b64decode(text)


def _raw_public(private: X25519PrivateKey) -> bytes:
    return private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def _raw_private(private: X25519PrivateKey) -> bytes:
    return private.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                                 serialization.NoEncryption())


def _wrap_key(passphrase: str, salt: bytes, iterations: int) -> bytes:
    return PBKDF2HMAC(hashes.SHA256(), 32, salt, iterations).derive(passphrase.encode())


@dataclass
class Identity:
    user_id: str
    private: X25519PrivateKey

    @property
    def public(self) -> bytes:
        return _raw_public(self.private)

    @classmethod
    def generate(cls, user_id: str) -> "Identity":
        return cls(user_id, X25519PrivateKey.generate())

    def key_upload(self, passphrase: str, iterations: int = 100_000) -> dict:
        """Body for PUT /me/chat-key."""
        salt, nonce = os.urandom(16), os.urandom(12)
        sealed = AESGCM(_wrap_key(passphrase, salt, iterations)).encrypt(
            nonce, _raw_private(self.private), f"{BACKUP_AAD}|{self.user_id}".encode())
        return {"public_key": b64(self.public), "key_backup": b64(nonce + sealed), "backup_salt": b64(salt),
                "backup_kdf": "pbkdf2-sha256", "backup_iterations": iterations}

    def server_held_upload(self) -> dict:
        """Body for PUT /me/chat-key with no passphrase: the server keeps the plain private key."""
        return {"public_key": b64(self.public), "key_backup": b64(_raw_private(self.private)), "backup_kdf": "none"}

    @classmethod
    def restore(cls, user_id: str, backup: dict, passphrase: str) -> "Identity":
        """Unlock GET /me/chat-key on a new device. Raises InvalidTag for a wrong passphrase."""
        blob = unb64(backup["key_backup"])
        key = _wrap_key(passphrase, unb64(backup["backup_salt"]), backup["backup_iterations"])
        raw = AESGCM(key).decrypt(blob[:12], blob[12:], f"{BACKUP_AAD}|{user_id}".encode())
        return cls(user_id, X25519PrivateKey.from_private_bytes(raw))


def conversation_key(mine: Identity, their_public: bytes, conversation_id: str) -> bytes:
    shared = mine.private.exchange(X25519PublicKey.from_public_bytes(their_public))
    low, high = sorted([mine.public, their_public])
    info = f"{PROTOCOL}|conv={conversation_id}|".encode() + low + high
    return HKDF(hashes.SHA256(), 32, PROTOCOL.encode(), info).derive(shared)


def _aad(conversation_id: str, message_id: str, sender_id: str, kind: str) -> bytes:
    return f"{PROTOCOL}|{conversation_id}|{message_id}|{sender_id}|{kind}".encode()


def encrypt(mine: Identity, their_public: bytes, conversation_id: str, content: dict, kind: str = "text",
            message_id: str | None = None) -> dict:
    """Message fields for POST .../messages, minus the key ids."""
    message_id = message_id or str(uuid.uuid4())
    nonce = os.urandom(12)
    plaintext = json.dumps({"v": 1, "type": kind, **content}).encode()
    sealed = AESGCM(conversation_key(mine, their_public, conversation_id)).encrypt(
        nonce, plaintext, _aad(conversation_id, message_id, mine.user_id, kind))
    return {"id": message_id, "kind": kind, "nonce": b64(nonce), "ciphertext": b64(sealed)}


def decrypt(mine: Identity, their_public: bytes, message: dict) -> dict:
    """Open a message from the API (sent by either person). Raises InvalidTag if anything was altered.
    The key and associated data use crypto_context_id (the conversation id, or for messages from
    before rev 10 the per-listing chat they were written in)."""
    context = message.get("crypto_context_id") or message["conversation_id"]
    key = conversation_key(mine, their_public, context)
    plaintext = AESGCM(key).decrypt(
        unb64(message["nonce"]), unb64(message["ciphertext"]),
        _aad(context, message["id"], message["sender_id"], message["kind"]))
    return json.loads(plaintext)


def safety_number(user_a: str, public_a: bytes, user_b: str, public_b: bytes) -> str:
    (ua, pa), (ub, pb) = sorted([(user_a, public_a), (user_b, public_b)])
    digest = hashlib.sha512(b"campushub-safety-v1" + ua.encode() + pa + ub.encode() + pb).digest()
    return " ".join(f"{int.from_bytes(digest[i * 5:i * 5 + 5], 'big') % 100000:05d}" for i in range(12))
