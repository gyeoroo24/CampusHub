"""Encrypted messaging between two people (rev 10: one chat per person).

A conversation is a pair of people, like a WhatsApp chat. What part of it is about is a topic: a
listing, a lost report or a found report ("Message seller" on a listing opens the chat with that
person and adds the listing as a topic). A message has at most one topic; offers always have a
listing topic. General messages (e.g. academic help) have none.

Each user's app makes an X25519 key pair; the two people's apps derive the same AES-256-GCM key
and only nonce + ciphertext reach this API. The key is bound to the message's crypto_context_id:
the conversation id, or for messages from before rev 10 the id of the per-listing chat they were
written in (see db/migrations/010_chat_per_person.sql). What the server does see, and enforces:

  - who may talk: only the two people in a conversation can read or write it. Everyone else,
    admins and moderators included, gets 404, as if it didn't exist. Blocked people can't send,
    and nobody can open a chat about their own listing or report.
  - which keys a message uses: it must name both people's current keys (409 otherwise), so no app
    keeps encrypting to a key its owner has replaced.
  - offers: the amount is inside the ciphertext, but the status (pending, accepted, declined,
    withdrawn, superseded) is kept here, and only the other person can accept or decline.

Sync: every change in a conversation (a message, an offer answered, a message unsent) takes the
next number from chat_conversations.last_seq while holding that row's lock, and stamps it on the
message as changed_seq. GET .../messages?after=N returns every change after N, so a client that
has seen everything up to N never misses one, whatever order transactions commit in.

Key backup: for now the app uploads its private key in plain form (backup_kdf "none"), so the user
never needs a passphrase and any browser they sign in on can read their messages. GET /me/chat-key
returns it to its owner only, but the server itself CAN read every message: this is not true
end-to-end encryption yet (true E2E, e.g. passkeys plus device linking, is a planned improvement). Older keys may
still have a passphrase-encrypted backup ("pbkdf2-sha256"); the app replaces it with a plain one
the next time it is unlocked.

Notifications say who wrote and about which listing, never what they wrote.
"""
import base64
import binascii
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

import asyncpg
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from pydantic import BaseModel, BeforeValidator, Field, PlainSerializer, PrivateAttr, WithJsonSchema, model_validator

from ..auth import CurrentUser, current_user
from ..common import UserRef, forbidden, not_found
from ..db import get_conn
from ..notify import create_notifications, deliver_push
from ..storage import file_url

router = APIRouter(tags=["Messages"])

# Sending more than this many messages in a minute gets 429.
MAX_MESSAGES_PER_MINUTE = 30


def _decode_base64(value):
    if isinstance(value, bytes):   # from the database
        return value
    if not isinstance(value, str):
        raise ValueError("must be base64 text")
    try:
        return base64.b64decode(value, validate=True)
    except binascii.Error as exc:
        raise ValueError("must be base64 text") from exc


Base64Bytes = Annotated[
    bytes,
    BeforeValidator(_decode_base64),
    PlainSerializer(lambda b: base64.b64encode(b).decode(), return_type=str),
    WithJsonSchema({"type": "string", "format": "base64"}),
]


# ---------------------------------------------------------------------------------------- models
class ChatKeyIn(BaseModel):
    public_key: Base64Bytes = Field(min_length=32, max_length=32, description="X25519 public key")
    key_backup: Base64Bytes = Field(min_length=32, max_length=512,
                                    description='"none": the 32-byte private key. "pbkdf2-sha256": the private '
                                                "key AES-GCM encrypted with a passphrase key (nonce + ciphertext + tag)")
    backup_salt: Base64Bytes | None = Field(None, min_length=16, max_length=64)
    backup_kdf: Literal["none", "pbkdf2-sha256"] = "none"
    backup_iterations: int | None = Field(None, ge=100_000, le=10_000_000)

    @model_validator(mode="after")
    def _backup_matches_kdf(self):
        if self.backup_kdf == "none":
            if len(self.key_backup) != 32 or self.backup_salt is not None or self.backup_iterations is not None:
                raise ValueError('backup_kdf "none" takes the 32-byte private key and no salt or iterations')
        elif len(self.key_backup) < 44 or self.backup_salt is None or self.backup_iterations is None:
            raise ValueError('backup_kdf "pbkdf2-sha256" needs an encrypted key_backup, backup_salt and backup_iterations')
        return self


class MyChatKey(BaseModel):
    id: UUID
    public_key: Base64Bytes
    key_backup: Base64Bytes
    backup_salt: Base64Bytes | None
    backup_kdf: str
    backup_iterations: int | None
    created_at: datetime


class PublicChatKey(BaseModel):
    id: UUID
    user_id: UUID
    public_key: Base64Bytes
    created_at: datetime
    is_current: bool


class EncryptedMessage(BaseModel):
    id: UUID
    conversation_id: UUID
    crypto_context_id: UUID = Field(description="The id the ciphertext is bound to (key derivation and associated "
                                                "data). Equals conversation_id except for pre-rev-10 messages")
    topic_id: UUID | None = Field(description="What it is about; null for general chat")
    seq: int = Field(description="Order in the conversation")
    changed_seq: int = Field(description="Last change; pass the highest one seen as ?after= to sync")
    sender_id: UUID
    kind: Literal["text", "offer"]
    sender_key_id: UUID
    recipient_key_id: UUID
    nonce: Base64Bytes | None = Field(description="null once unsent")
    ciphertext: Base64Bytes | None = Field(description="null once unsent")
    offer_status: Literal["pending", "accepted", "declined", "withdrawn", "superseded"] | None
    offer_answered_at: datetime | None
    sent_at: datetime
    deleted_at: datetime | None


class ChatTopic(BaseModel):
    id: UUID
    kind: Literal["listing", "lost_report", "found_report"]
    ref_id: UUID = Field(description="The listing, lost report or found report")
    owner_id: UUID = Field(description="The seller, or whoever filed the report")
    title: str
    description: str | None = Field(description="Lost & Found: the report's description")
    price: Decimal | None = Field(description="Listings only")
    status: str = Field(description="Listing: available/reserved/sold. Report: open/closed")
    cover_photo_url: str | None
    is_removed: bool
    started_by: UUID
    created_at: datetime


class ChatPeer(BaseModel):
    id: UUID
    name: str
    is_active: bool
    key: PublicChatKey | None = Field(description="Their current key; null until they set up messaging")


class Conversation(BaseModel):
    id: UUID
    peer: ChatPeer
    topics: list[ChatTopic] = Field(description="Oldest first")
    my_key_id: UUID | None = Field(description="My current key; null until I set up messaging")
    last_seq: int
    my_last_read_seq: int
    peer_last_read_seq: int = Field(description="Read receipts: the peer has read my messages up to this seq")
    unread_count: int
    last_message: EncryptedMessage | None
    last_message_at: datetime | None
    created_at: datetime
    blocked_by_me: bool
    can_send: bool
    cant_send_reason: str | None
    _cant_send_status: int | None = PrivateAttr(None)
    _i_am_a: bool = PrivateAttr(True)


class ConversationStart(BaseModel):
    """Exactly one: what to talk about, or (general chat) just who with."""
    listing_id: UUID | None = None
    lost_report_id: UUID | None = None
    found_report_id: UUID | None = None
    user_id: UUID | None = None

    @model_validator(mode="after")
    def _exactly_one(self):
        if sum(v is not None for v in (self.listing_id, self.lost_report_id, self.found_report_id, self.user_id)) != 1:
            raise ValueError("Send exactly one of listing_id, lost_report_id, found_report_id, user_id")
        return self


class StartedConversation(BaseModel):
    conversation: Conversation
    topic_id: UUID | None = Field(description="The topic asked for; null for a general chat")


class MessageIn(BaseModel):
    id: UUID = Field(description="Chosen by the app (UUID v4); it is part of the ciphertext's associated data, "
                                 "and resending the same message after a network error is safe")
    kind: Literal["text", "offer"] = "text"
    topic_id: UUID | None = Field(None, description="What it is about; required for an offer (a listing topic)")
    sender_key_id: UUID
    recipient_key_id: UUID
    nonce: Base64Bytes = Field(min_length=12, max_length=12)
    ciphertext: Base64Bytes = Field(min_length=17, max_length=16400)


class MessagePage(BaseModel):
    conversation: Conversation
    items: list[EncryptedMessage]
    keys: list[PublicChatKey] = Field(description="Every key the items use, to decrypt them")
    has_more: bool


class ReadIn(BaseModel):
    seq: int = Field(ge=0, description="I have read everything up to this seq")


class OfferAction(BaseModel):
    action: Literal["accept", "decline", "withdraw"]


class UnreadCount(BaseModel):
    unread_messages: int
    conversations: int


# ------------------------------------------------------------------------------------- queries
def _message_columns(alias: str = "") -> str:
    a = f"{alias}." if alias else ""
    return (f"{a}id, {a}conversation_id, {a}crypto_context_id, {a}topic_id, {a}seq, {a}changed_seq, {a}sender_id, "
            f"{a}kind::text AS kind, {a}sender_key_id, {a}recipient_key_id, {a}nonce, {a}ciphertext, "
            f"{a}offer_status::text AS offer_status, {a}offer_answered_at, {a}sent_at, {a}deleted_at")


_MESSAGE_COLUMNS = _message_columns()

_MY_READ = "CASE WHEN c.user_a = $1 THEN c.user_a_last_read_seq ELSE c.user_b_last_read_seq END"
# rev 19: deleting a chat hides it from that person only: messages up to this seq stay hidden for them.
_MY_CLEARED = "CASE WHEN c.user_a = $1 THEN c.user_a_cleared_seq ELSE c.user_b_cleared_seq END"
# ... and "delete for me" hides single messages from that person only.
_VISIBLE_TO_ME = f"""m.seq > {_MY_CLEARED}
    AND NOT EXISTS (SELECT 1 FROM chat_message_hides h WHERE h.message_id = m.id AND h.user_id = $1)"""

# $1 is the caller. Callers add "AND ..." conditions on c and an ORDER BY.
_CONVERSATIONS = f"""
SELECT c.id, c.last_seq, c.last_message_at, c.created_at,
       (c.user_a = $1) AS i_am_a,
       {_MY_READ} AS my_read,
       CASE WHEN c.user_a = $1 THEN c.user_b_last_read_seq ELSE c.user_a_last_read_seq END AS peer_read,
       p.id AS peer_id, p.name AS peer_name, p.is_active AS peer_active,
       pk.id AS peer_key_id, pk.public_key AS peer_public_key, pk.created_at AS peer_key_created_at,
       mk.id AS my_key_id,
       EXISTS (SELECT 1 FROM chat_blocks b WHERE b.blocker_id = $1 AND b.blocked_id = p.id) AS blocked_by_me,
       EXISTS (SELECT 1 FROM chat_blocks b WHERE b.blocker_id = p.id AND b.blocked_id = $1) AS blocked_me,
       (SELECT count(*) FROM chat_messages m
        WHERE m.conversation_id = c.id AND m.sender_id <> $1 AND m.deleted_at IS NULL AND m.seq > {_MY_READ}
          AND {_VISIBLE_TO_ME}
       ) AS unread_count,
       lm.id AS lm_id
FROM chat_conversations c
JOIN users p ON p.id = CASE WHEN c.user_a = $1 THEN c.user_b ELSE c.user_a END
LEFT JOIN chat_keys pk ON pk.user_id = p.id AND pk.retired_at IS NULL
LEFT JOIN chat_keys mk ON mk.user_id = $1 AND mk.retired_at IS NULL
LEFT JOIN LATERAL (SELECT m.id FROM chat_messages m WHERE m.conversation_id = c.id AND {_VISIBLE_TO_ME}
                   ORDER BY m.seq DESC LIMIT 1) lm ON true
WHERE (c.user_a = $1 OR c.user_b = $1)
"""

# Topics of the conversations in $1, with what each one is about.
_TOPICS = """
SELECT t.id, t.conversation_id, t.kind::text AS kind, t.started_by, t.created_at,
       coalesce(t.listing_id, t.lost_report_id, t.found_report_id) AS ref_id,
       coalesce(l.seller_id, t.listing_seller_id, lr.reporter_id, fr.reporter_id) AS owner_id,
       CASE t.kind WHEN 'listing' THEN coalesce(l.title, t.listing_title, 'Deleted listing')
                   WHEN 'lost_report' THEN 'Lost: ' || coalesce(lr.title, lc.name)
                   ELSE 'Found: ' || coalesce(fr.title, fc.name) END AS title,
       coalesce(lr.description, fr.description) AS description,
       l.price,
       coalesce(l.status::text, lr.status::text, fr.status::text, 'available') AS status,
       -- A deleted listing is gone from the database (rev 23); its topic keeps the title and seller.
       coalesce(l.deleted_at, lr.deleted_at, fr.deleted_at) IS NOT NULL
         OR (t.kind = 'listing' AND l.id IS NULL) AS is_removed,
       CASE t.kind
         WHEN 'listing' THEN (SELECT ph.s3_key FROM listing_photos ph WHERE ph.listing_id = l.id
                              ORDER BY ph.sort_order LIMIT 1)
         WHEN 'lost_report' THEN (SELECT ph.s3_key FROM lost_report_photos ph WHERE ph.lost_report_id = lr.id
                                  ORDER BY ph.sort_order LIMIT 1)
         ELSE (SELECT ph.s3_key FROM found_report_photos ph WHERE ph.found_report_id = fr.id
               ORDER BY ph.sort_order LIMIT 1)
       END AS cover_key
FROM chat_topics t
LEFT JOIN listings l ON l.id = t.listing_id
LEFT JOIN lost_reports lr ON lr.id = t.lost_report_id
LEFT JOIN lf_categories lc ON lc.id = lr.category_id
LEFT JOIN found_reports fr ON fr.id = t.found_report_id
LEFT JOIN lf_categories fc ON fc.id = fr.category_id
WHERE t.conversation_id = ANY($1::uuid[])
ORDER BY t.created_at, t.id
"""


def _message(r: asyncpg.Record) -> EncryptedMessage:
    return EncryptedMessage(**{k: r[k] for k in EncryptedMessage.model_fields})


def _cant_send(r: asyncpg.Record) -> tuple[int, str] | None:
    """Why the caller can't send here, with the status a send gets: 403 not allowed, 409 a key is missing.
    Someone who has been blocked isn't told so."""
    if r["blocked_by_me"]:
        return 403, f"You blocked {r['peer_name']}. Unblock them to send messages."
    if r["blocked_me"]:
        return 403, "You can't send messages in this conversation."
    if not r["peer_active"]:
        return 403, f"{r['peer_name']}'s account has been deactivated."
    if r["my_key_id"] is None:
        return 409, "Set up secure messaging to send messages."
    if r["peer_key_id"] is None:
        return 409, f"{r['peer_name']} hasn't set up secure messaging yet. We've let them know you want to chat."
    return None


def _topic(r: asyncpg.Record) -> ChatTopic:
    return ChatTopic(**{k: r[k] for k in ChatTopic.model_fields if k != "cover_photo_url"},
                     cover_photo_url=file_url(r["cover_key"]) if r["cover_key"] else None)


async def _conversations(conn: asyncpg.Connection, user: CurrentUser, where: str, *args) -> list[Conversation]:
    rows = await conn.fetch(_CONVERSATIONS + where, user.id, *args)
    last_ids = [r["lm_id"] for r in rows if r["lm_id"]]
    last = {m["id"]: _message(m) for m in await conn.fetch(
        f"SELECT {_MESSAGE_COLUMNS} FROM chat_messages WHERE id = ANY($1::uuid[])", last_ids)} if last_ids else {}
    topics: dict[UUID, list[ChatTopic]] = {}
    if rows:
        for t in await conn.fetch(_TOPICS, [r["id"] for r in rows]):
            topics.setdefault(t["conversation_id"], []).append(_topic(t))
    result = []
    for r in rows:
        cant_send = _cant_send(r)
        peer_key = (PublicChatKey(id=r["peer_key_id"], user_id=r["peer_id"], public_key=r["peer_public_key"],
                                  created_at=r["peer_key_created_at"], is_current=True)
                    if r["peer_key_id"] else None)
        result.append(Conversation(
            id=r["id"],
            peer=ChatPeer(id=r["peer_id"], name=r["peer_name"], is_active=r["peer_active"], key=peer_key),
            topics=topics.get(r["id"], []),
            my_key_id=r["my_key_id"],
            last_seq=r["last_seq"], my_last_read_seq=r["my_read"], peer_last_read_seq=r["peer_read"],
            unread_count=r["unread_count"],
            last_message=last.get(r["lm_id"]),
            last_message_at=r["last_message_at"], created_at=r["created_at"],
            blocked_by_me=r["blocked_by_me"], can_send=cant_send is None,
            cant_send_reason=cant_send[1] if cant_send else None))
        result[-1]._cant_send_status = cant_send[0] if cant_send else None
        result[-1]._i_am_a = r["i_am_a"]
    return result


async def _ensure_keys(conn: asyncpg.Connection, *user_ids: UUID) -> None:
    """Give anyone without a messaging key one, so they can be written to before they ever open
    Messages. The server holds every key anyway (backup_kdf "none"; see the module docstring), so
    making it here is no weaker than their app making it and uploading it."""
    for user_id in user_ids:
        private = X25519PrivateKey.generate()
        await conn.execute(
            """INSERT INTO chat_keys (user_id, public_key, key_backup, backup_kdf)
               SELECT $1, $2, $3, 'none'
               WHERE NOT EXISTS (SELECT 1 FROM chat_keys WHERE user_id = $1 AND retired_at IS NULL)
               ON CONFLICT (user_id) WHERE retired_at IS NULL DO NOTHING""",
            user_id,
            private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw),
            private.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                                  serialization.NoEncryption()))


async def _conversation(conn: asyncpg.Connection, conversation_id: UUID, user: CurrentUser) -> Conversation:
    """The conversation, if the caller is in it. Anyone else gets 404, not 403: they can't tell it exists."""
    users = await conn.fetchrow(
        "SELECT user_a, user_b FROM chat_conversations WHERE id = $1 AND (user_a = $2 OR user_b = $2)",
        conversation_id, user.id)
    if users is not None:
        await _ensure_keys(conn, users["user_a"], users["user_b"])
    found = await _conversations(conn, user, " AND c.id = $2", conversation_id)
    if not found:
        raise not_found("Conversation")
    return found[0]


async def _is_blocked(conn: asyncpg.Connection, a: UUID, b: UUID) -> bool:
    """Has either of a and b blocked the other?"""
    return await conn.fetchval(
        """SELECT EXISTS (SELECT 1 FROM chat_blocks
                          WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))""",
        a, b)


async def _next_seq(conn: asyncpg.Connection, conversation_id: UUID) -> int:
    """Take the conversation's next change number. Holds the row lock until the transaction ends."""
    return await conn.fetchval(
        "UPDATE chat_conversations SET last_seq = last_seq + 1 WHERE id = $1 RETURNING last_seq", conversation_id)


def _read_column(conv: Conversation, mine: bool) -> str:
    """Column names come from this fixed choice, never from the request."""
    return "user_a_last_read_seq" if conv._i_am_a == mine else "user_b_last_read_seq"


async def _message_in_my_conversation(conn: asyncpg.Connection, message_id: UUID,
                                      user: CurrentUser) -> asyncpg.Record:
    row = await conn.fetchrow(
        f"""SELECT {_message_columns("m")}, t.listing_id
            FROM chat_messages m JOIN chat_conversations c ON c.id = m.conversation_id
            LEFT JOIN chat_topics t ON t.id = m.topic_id
            WHERE m.id = $1 AND (c.user_a = $2 OR c.user_b = $2)""",
        message_id, user.id)
    if row is None:
        raise not_found("Message")
    return row


# ------------------------------------------------------------------------------------------ keys
@router.get("/me/chat-key", response_model=MyChatKey,
            summary="My messaging key, with its private key (only ever returned to me)")
async def get_my_chat_key(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(
        """SELECT id, public_key, key_backup, backup_salt, backup_kdf, backup_iterations, created_at
           FROM chat_keys WHERE user_id = $1 AND retired_at IS NULL""", user.id)
    if row is None:
        raise HTTPException(404, "You haven't set up secure messaging yet.")
    return MyChatKey(**dict(row))


@router.put("/me/chat-key", response_model=MyChatKey,
            summary="Set up messaging, update the key backup (same public key), or replace my key",
            responses={201: {"description": "A new key: messages sent to the old one can no longer be read"}})
async def put_my_chat_key(body: ChatKeyIn, response: Response, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    async with conn.transaction():
        current = await conn.fetchrow(
            "SELECT id, public_key FROM chat_keys WHERE user_id = $1 AND retired_at IS NULL FOR UPDATE", user.id)
        if current is not None and current["public_key"] == body.public_key:
            # Same key, new backup (e.g. a passphrase backup moved to "none").
            row = await conn.fetchrow(
                """UPDATE chat_keys SET key_backup = $2, backup_salt = $3, backup_kdf = $4, backup_iterations = $5
                   WHERE id = $1
                   RETURNING id, public_key, key_backup, backup_salt, backup_kdf, backup_iterations, created_at""",
                current["id"], body.key_backup, body.backup_salt, body.backup_kdf, body.backup_iterations)
            response.status_code = 200
        else:
            if current is not None:
                await conn.execute("UPDATE chat_keys SET retired_at = now() WHERE id = $1", current["id"])
            row = await conn.fetchrow(
                """INSERT INTO chat_keys (user_id, public_key, key_backup, backup_salt, backup_kdf, backup_iterations)
                   VALUES ($1, $2, $3, $4, $5, $6)
                   RETURNING id, public_key, key_backup, backup_salt, backup_kdf, backup_iterations, created_at""",
                user.id, body.public_key, body.key_backup, body.backup_salt, body.backup_kdf, body.backup_iterations)
            response.status_code = 201
    return MyChatKey(**dict(row))


@router.get("/users/{user_id}/chat-key", response_model=PublicChatKey,
            summary="Someone's current public messaging key (signed-in users)")
async def get_user_chat_key(user_id: UUID, _: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(
        "SELECT id, user_id, public_key, created_at FROM chat_keys WHERE user_id = $1 AND retired_at IS NULL",
        user_id)
    if row is None:
        raise HTTPException(404, "This person hasn't set up secure messaging yet.")
    return PublicChatKey(**dict(row), is_current=True)


# --------------------------------------------------------------------------------- conversations
@router.get("/chat/conversations", response_model=list[Conversation],
            summary="My conversations, most recent first")
async def list_conversations(limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0, le=10_000),
                             user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    # Whoever opened a chat sees it straight away; the other person from the first message. A chat
    # someone deleted comes back only with a newer message.
    return await _conversations(
        conn, user,
        f""" AND (lm.id IS NOT NULL OR (c.last_message_at IS NULL AND c.created_by = $1 AND {_MY_CLEARED} = 0))
            ORDER BY coalesce(c.last_message_at, c.created_at) DESC, c.id DESC LIMIT $2 OFFSET $3""",
        limit, offset)


@router.get("/chat/unread", response_model=UnreadCount, summary="Unread messages, for the app-bar badge")
async def unread_count(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow(
        f"""SELECT count(*) AS unread_messages, count(DISTINCT m.conversation_id) AS conversations
           FROM chat_conversations c
           JOIN chat_messages m ON m.conversation_id = c.id AND m.sender_id <> $1 AND m.deleted_at IS NULL
           WHERE (c.user_a = $1 OR c.user_b = $1) AND m.seq > {_MY_READ} AND {_VISIBLE_TO_ME}""", user.id)
    return UnreadCount(**dict(row))


# What a chat can be about: (topic kind, its column in chat_topics, the SQL that finds its owner).
_TOPIC_TARGETS = {
    "listing_id": ("listing", "listing_id",
                   "SELECT seller_id AS owner_id, title FROM listings WHERE id = $1 AND deleted_at IS NULL"),
    "lost_report_id": ("lost_report", "lost_report_id",
                       """SELECT r.reporter_id AS owner_id, 'Lost: ' || coalesce(r.title, c.name) AS title FROM lost_reports r
                          JOIN lf_categories c ON c.id = r.category_id WHERE r.id = $1 AND r.deleted_at IS NULL"""),
    "found_report_id": ("found_report", "found_report_id",
                        """SELECT r.reporter_id AS owner_id, 'Found: ' || coalesce(r.title, c.name) AS title FROM found_reports r
                           JOIN lf_categories c ON c.id = r.category_id WHERE r.id = $1 AND r.deleted_at IS NULL"""),
}


@router.post("/chat/conversations", response_model=StartedConversation,
             summary="Open my chat with someone: about a listing or Lost & Found report (added as a topic), or general",
             responses={201: {"description": "A new conversation or topic"}})
async def start_conversation(body: ConversationStart, response: Response,
                             user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    field = next(f for f in ("listing_id", "lost_report_id", "found_report_id", "user_id") if getattr(body, f))
    target: UUID = getattr(body, field)
    if field == "user_id":
        owner_id = await conn.fetchval("SELECT id FROM users WHERE id = $1", target)
        if owner_id is None:
            raise not_found("User")
        if owner_id == user.id:
            raise HTTPException(422, "You can't message yourself.")
    else:
        kind, column, lookup = _TOPIC_TARGETS[field]
        found = await conn.fetchrow(lookup, target)
        if found is None:
            raise not_found("Listing" if kind == "listing" else "Report")
        owner_id = found["owner_id"]
        if owner_id == user.id:
            raise HTTPException(422, "This is your own post. Messages about it show up in Messages.")
    peer = await conn.fetchrow("SELECT is_active FROM users WHERE id = $1", owner_id)

    existing = await conn.fetchval(
        "SELECT id FROM chat_conversations WHERE user_a = LEAST($1::uuid, $2::uuid) AND user_b = GREATEST($1::uuid, $2::uuid)",
        user.id, owner_id)
    topic_id = None
    if existing is not None and field != "user_id":
        topic_id = await conn.fetchval(
            f"SELECT id FROM chat_topics WHERE conversation_id = $1 AND {column} = $2", existing, target)
    if existing is not None and (field == "user_id" or topic_id is not None):
        response.status_code = 200
        return StartedConversation(conversation=await _conversation(conn, existing, user), topic_id=topic_id)
    if await _is_blocked(conn, user.id, owner_id):
        raise forbidden("You can't message this person.")
    if not peer["is_active"]:
        raise HTTPException(422, "This person's account has been deactivated.")

    async with conn.transaction():
        conversation_id = existing or await conn.fetchval(
            """INSERT INTO chat_conversations (user_a, user_b, created_by)
               VALUES (LEAST($1::uuid, $2::uuid), GREATEST($1::uuid, $2::uuid), $1)
               ON CONFLICT (user_a, user_b) DO UPDATE SET user_a = EXCLUDED.user_a RETURNING id""",
            user.id, owner_id)
        if field != "user_id":
            # Column names come from _TOPIC_TARGETS, never from the request.
            topic_id = await conn.fetchval(
                f"""INSERT INTO chat_topics (conversation_id, kind, {column}, started_by)
                    VALUES ($1, $2::chat_topic_kind, $3, $4)
                    ON CONFLICT (conversation_id, {column}) DO UPDATE SET started_by = chat_topics.started_by
                    RETURNING id""",
                conversation_id, kind, target, user.id)
            if kind == "listing":
                # Kept so the chat still says what it was about after the listing is deleted.
                await conn.execute(
                    "UPDATE chat_topics SET listing_title = $2, listing_seller_id = $3 WHERE id = $1",
                    topic_id, found["title"], owner_id)
    response.status_code = 201
    return StartedConversation(conversation=await _conversation(conn, conversation_id, user), topic_id=topic_id)


@router.get("/chat/conversations/{conversation_id}", response_model=Conversation, summary="One of my conversations")
async def get_conversation(conversation_id: UUID, user: CurrentUser = Depends(current_user),
                           conn: asyncpg.Connection = Depends(get_conn)):
    return await _conversation(conn, conversation_id, user)


@router.get("/chat/conversations/{conversation_id}/messages", response_model=MessagePage,
            summary="Encrypted messages: the latest page, older ones (?before=seq), or changes (?after=seq)")
async def list_messages(conversation_id: UUID,
                        after: int | None = Query(None, ge=0, description="Changes after this changed_seq, oldest first"),
                        before: int | None = Query(None, ge=1, description="Messages before this seq (older history)"),
                        limit: int = Query(50, ge=1, le=100),
                        user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    if after is not None and before is not None:
        raise HTTPException(422, "Send either after or before, not both.")
    conversation = await _conversation(conn, conversation_id, user)
    # Messages the caller deleted (a whole chat up to a point, or one by one) never come back to them.
    visible = f"""AND m.seq > (SELECT {_MY_CLEARED.replace('$1', '$4')} FROM chat_conversations c WHERE c.id = $1)
                  AND NOT EXISTS (SELECT 1 FROM chat_message_hides h WHERE h.message_id = m.id AND h.user_id = $4)"""
    if after is not None:
        rows = await conn.fetch(
            f"""SELECT {_MESSAGE_COLUMNS} FROM chat_messages m WHERE conversation_id = $1 AND changed_seq > $2 {visible}
                ORDER BY changed_seq, seq LIMIT $3""", conversation_id, after, limit + 1, user.id)
        has_more = len(rows) > limit
        rows = rows[:limit]
    else:
        rows = await conn.fetch(
            f"""SELECT {_MESSAGE_COLUMNS} FROM chat_messages m
                WHERE conversation_id = $1 AND ($2::bigint IS NULL OR seq < $2) {visible}
                ORDER BY seq DESC LIMIT $3""", conversation_id, before, limit + 1, user.id)
        has_more = len(rows) > limit
        rows = list(reversed(rows[:limit]))
    key_ids = list({r["sender_key_id"] for r in rows} | {r["recipient_key_id"] for r in rows})
    keys = await conn.fetch(
        """SELECT id, user_id, public_key, created_at, retired_at IS NULL AS is_current
           FROM chat_keys WHERE id = ANY($1::uuid[])""", key_ids) if key_ids else []
    return MessagePage(conversation=conversation, items=[_message(r) for r in rows],
                       keys=[PublicChatKey(**dict(k)) for k in keys], has_more=has_more)


@router.post("/chat/conversations/{conversation_id}/messages", response_model=EncryptedMessage, status_code=201,
             summary="Send an encrypted message or offer",
             responses={200: {"description": "This message was already sent (a retry)"},
                        409: {"description": "A key has changed: fetch the conversation again and re-encrypt"},
                        429: {"description": "Too many messages; wait a minute"}})
async def send_message(conversation_id: UUID, body: MessageIn, response: Response, background: BackgroundTasks,
                       user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    conversation = await _conversation(conn, conversation_id, user)
    existing = await conn.fetchrow(f"SELECT {_MESSAGE_COLUMNS} FROM chat_messages WHERE id = $1", body.id)
    if existing is not None:
        same = (existing["conversation_id"] == conversation_id and existing["sender_id"] == user.id
                and existing["nonce"] == body.nonce and existing["ciphertext"] == body.ciphertext)
        if not same:
            raise HTTPException(409, "This message id is already used. Send it again with a new id.")
        response.status_code = 200
        return _message(existing)
    if not conversation.can_send:
        raise HTTPException(conversation._cant_send_status, conversation.cant_send_reason)
    if body.sender_key_id != conversation.my_key_id or body.recipient_key_id != conversation.peer.key.id:
        raise HTTPException(409, "A messaging key has changed since this message was encrypted. "
                                 "Reload the conversation and send it again.")
    topic = next((t for t in conversation.topics if t.id == body.topic_id), None)
    if body.topic_id is not None and topic is None:
        raise HTTPException(422, "That topic isn't part of this conversation.")
    if body.kind == "offer":
        if topic is None or topic.kind != "listing":
            raise HTTPException(422, "An offer has to be about one of the listings in this chat (send its topic_id).")
        if topic.is_removed or topic.status == "sold":
            raise HTTPException(422, "This listing is no longer for sale, so it can't take offers.")
    recent = await conn.fetchval(
        "SELECT count(*) FROM chat_messages WHERE sender_id = $1 AND sent_at > now() - interval '1 minute'", user.id)
    if recent >= MAX_MESSAGES_PER_MINUTE:
        raise HTTPException(429, "You're sending messages too fast. Wait a minute and try again.")

    peer_id = conversation.peer.id
    payload = {}
    notified: list[UUID] = []
    async with conn.transaction():
        seq = await _next_seq(conn, conversation_id)
        await conn.execute(
            f"UPDATE chat_conversations SET last_message_at = now(), {_read_column(conversation, mine=True)} = $2 "
            "WHERE id = $1", conversation_id, seq)
        if body.kind == "offer":
            # One open offer per listing: a new one (from either person) replaces it.
            await conn.execute(
                """UPDATE chat_messages SET offer_status = 'superseded', offer_answered_at = now(), changed_seq = $2
                   WHERE topic_id = $1 AND offer_status = 'pending'""", body.topic_id, seq)
        row = await conn.fetchrow(
            f"""INSERT INTO chat_messages (id, conversation_id, crypto_context_id, topic_id, seq, changed_seq,
                                           sender_id, kind, sender_key_id, recipient_key_id, nonce, ciphertext,
                                           offer_status)
                VALUES ($1, $2, $2, $10, $3, $3, $4, $5::chat_message_kind, $6, $7, $8, $9,
                        CASE WHEN $5::chat_message_kind = 'offer' THEN 'pending' END::chat_offer_status)
                RETURNING {_MESSAGE_COLUMNS}""",
            body.id, conversation_id, seq, user.id, body.kind, body.sender_key_id, body.recipient_key_id,
            body.nonce, body.ciphertext, body.topic_id)
        # Notify once per unread stretch: only when this is the first message they haven't read yet.
        earlier_unread = await conn.fetchval(
            f"""SELECT EXISTS (SELECT 1 FROM chat_messages m JOIN chat_conversations c ON c.id = m.conversation_id
                               WHERE m.conversation_id = $1 AND m.sender_id = $2 AND m.seq < $3
                                 AND m.deleted_at IS NULL AND m.seq > c.{_read_column(conversation, mine=False)})""",
            conversation_id, user.id, seq)
        if body.kind == "offer" or not earlier_unread:
            if body.kind == "offer":
                what = f"made you an offer on “{topic.title}”"
            else:
                what = f"sent you a message about “{topic.title}”" if topic else "sent you a message"
            payload = {"conversation_id": str(conversation_id), "message": f"{user.name} {what}"}
            notified = await create_notifications(conn, [peer_id], "chat_message", payload)
    background.add_task(deliver_push, notified, "chat_message", payload)
    return _message(row)


@router.post("/chat/conversations/{conversation_id}/read", summary="Mark messages read up to a seq")
async def mark_read(conversation_id: UUID, body: ReadIn, user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)) -> dict:
    conversation = await _conversation(conn, conversation_id, user)
    column = _read_column(conversation, mine=True)
    seq = await conn.fetchval(
        f"UPDATE chat_conversations SET {column} = GREATEST({column}, LEAST($2, last_seq)) WHERE id = $1 "
        f"RETURNING {column}", conversation_id, body.seq)
    return {"my_last_read_seq": seq}


@router.post("/chat/messages/{message_id}/offer", response_model=EncryptedMessage,
             summary="Accept (the listing becomes reserved) or decline the other person's offer, or withdraw my own")
async def answer_offer(message_id: UUID, body: OfferAction, background: BackgroundTasks,
                       user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    message = await _message_in_my_conversation(conn, message_id, user)
    if message["kind"] != "offer":
        raise HTTPException(422, "This message isn't an offer.")
    mine = message["sender_id"] == user.id
    if body.action == "withdraw" and not mine:
        raise forbidden("Only the person who made an offer can withdraw it.")
    if body.action != "withdraw" and mine:
        raise forbidden("You can't accept or decline your own offer.")
    status = {"accept": "accepted", "decline": "declined", "withdraw": "withdrawn"}[body.action]
    payload = {}
    notified: list[UUID] = []
    async with conn.transaction():
        listing = await conn.fetchrow(
            "SELECT title, status::text AS status, deleted_at FROM listings WHERE id = $1 FOR UPDATE",
            message["listing_id"])
        if body.action == "accept" and (listing is None or listing["status"] == "sold"):
            raise HTTPException(409, "This listing is no longer for sale.")
        seq = await _next_seq(conn, message["conversation_id"])
        row = await conn.fetchrow(
            f"""UPDATE chat_messages SET offer_status = $2, offer_answered_at = now(), changed_seq = $3
                WHERE id = $1 AND offer_status = 'pending' RETURNING {_MESSAGE_COLUMNS}""",
            message_id, status, seq)
        if row is None:
            raise HTTPException(409, "This offer is no longer open.")
        if body.action == "accept":
            # A deal is agreed: the listing is held for this buyer until the seller marks it sold
            # (or makes it available again).
            await conn.execute("UPDATE listings SET status = 'reserved' WHERE id = $1 AND status = 'available'",
                               message["listing_id"])
        if not mine:
            payload = {"conversation_id": str(message["conversation_id"]),
                       "message": f"{user.name} {status} your offer on “{listing['title'] if listing else 'a deleted listing'}”"}
            notified = await create_notifications(conn, [message["sender_id"]], "chat_message", payload)
    background.add_task(deliver_push, notified, "chat_message", payload)
    return _message(row)


@router.delete("/chat/messages/{message_id}", status_code=204,
               summary="Unsend my message: its ciphertext is erased for both people")
async def unsend_message(message_id: UUID, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    message = await _message_in_my_conversation(conn, message_id, user)
    if message["sender_id"] != user.id:
        raise forbidden("You can only unsend your own messages.")
    if message["deleted_at"] is None:
        async with conn.transaction():
            seq = await _next_seq(conn, message["conversation_id"])
            await conn.execute(
                """UPDATE chat_messages SET nonce = NULL, ciphertext = NULL, deleted_at = now(), changed_seq = $2,
                          offer_status = CASE WHEN offer_status = 'pending' THEN 'withdrawn' ELSE offer_status END,
                          offer_answered_at = CASE WHEN offer_status = 'pending' THEN now() ELSE offer_answered_at END
                   WHERE id = $1 AND deleted_at IS NULL""", message_id, seq)
    return Response(status_code=204)


@router.post("/chat/messages/{message_id}/hide", status_code=204,
             summary="Delete a message for me only; the other person still sees it")
async def hide_message(message_id: UUID, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    await _message_in_my_conversation(conn, message_id, user)
    await conn.execute("INSERT INTO chat_message_hides (user_id, message_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                       user.id, message_id)
    return Response(status_code=204)


@router.delete("/chat/conversations/{conversation_id}", status_code=204,
               summary="Delete a chat for me only: it leaves my list and its messages so far stay hidden from me")
async def delete_conversation(conversation_id: UUID, user: CurrentUser = Depends(current_user),
                              conn: asyncpg.Connection = Depends(get_conn)):
    """Nothing is erased: the other person keeps the whole chat. If they write again, the chat comes back for
    me with only the new messages."""
    done = await conn.fetchval(
        """UPDATE chat_conversations SET
               user_a_cleared_seq = CASE WHEN user_a = $2 THEN last_seq ELSE user_a_cleared_seq END,
               user_a_last_read_seq = CASE WHEN user_a = $2 THEN last_seq ELSE user_a_last_read_seq END,
               user_b_cleared_seq = CASE WHEN user_b = $2 THEN last_seq ELSE user_b_cleared_seq END,
               user_b_last_read_seq = CASE WHEN user_b = $2 THEN last_seq ELSE user_b_last_read_seq END
           WHERE id = $1 AND (user_a = $2 OR user_b = $2) RETURNING true""", conversation_id, user.id)
    if not done:
        raise not_found("Conversation")
    return Response(status_code=204)


# ---------------------------------------------------------------------------------------- blocks
@router.get("/chat/blocks", response_model=list[UserRef], summary="People I've blocked")
async def list_blocks(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    rows = await conn.fetch(
        """SELECT u.id, u.name FROM chat_blocks b JOIN users u ON u.id = b.blocked_id
           WHERE b.blocker_id = $1 ORDER BY b.created_at DESC""", user.id)
    return [UserRef(**dict(r)) for r in rows]


@router.put("/chat/blocks/{user_id}", status_code=204,
            summary="Block someone: they can no longer message me or start chats with me")
async def block_user(user_id: UUID, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    if user_id == user.id:
        raise HTTPException(422, "You can't block yourself.")
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)", user_id):
        raise not_found("User")
    await conn.execute("INSERT INTO chat_blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                       user.id, user_id)
    return Response(status_code=204)


@router.delete("/chat/blocks/{user_id}", status_code=204, summary="Unblock someone")
async def unblock_user(user_id: UUID, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    await conn.execute("DELETE FROM chat_blocks WHERE blocker_id = $1 AND blocked_id = $2", user.id, user_id)
    return Response(status_code=204)
