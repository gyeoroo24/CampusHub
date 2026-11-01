"""Encrypted messaging, one chat per pair of people with topics (app/routers/chat.py, rev 10).

The tests act as real clients with tests/chat_crypto.py, so they check both the API's rules
(who can see and do what) and that what it stores can only be read with the right keys.
"""
import uuid

import pytest
from cryptography.exceptions import InvalidTag

from .chat_crypto import Identity, _raw_private, b64, decrypt, encrypt, safety_number, unb64
from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, category, make_admin, sign_in, sql

PASS = "correct horse battery"


def _listing(client, seller=ASHA, title="Hero cycle", price="2500"):
    cat = category(client, seller, "buy-sell", "Cycles")
    r = client.post(f"{API}/listings", headers=seller, json={"title": title, "price": price, "category_id": cat})
    assert r.status_code == 201, r.text
    return r.json()


def _setup_keys(client, headers) -> Identity:
    me = Identity.generate(sign_in(client, headers))
    r = client.put(f"{API}/me/chat-key", headers=headers, json=me.key_upload(PASS))
    assert r.status_code == 201, r.text
    return me


def _start(client, buyer, listing_id=None, **target):
    """Open the chat about a listing (or any other target) and remember the topic it returned."""
    r = client.post(f"{API}/chat/conversations", headers=buyer,
                    json=target or {"listing_id": listing_id})
    assert r.status_code in (200, 201), r.text
    return r.json()["conversation"] | {"topic_id": r.json()["topic_id"]}


def _send(client, headers, me: Identity, conversation, content=None, kind="text", **overrides):
    """Encrypt for the conversation's current keys (as the app does) and send, about its topic."""
    conv = client.get(f"{API}/chat/conversations/{conversation['id']}", headers=headers).json()
    body = encrypt(me, unb64(conv["peer"]["key"]["public_key"]), conv["id"],
                   content or {"text": "Is it still available?"}, kind)
    body |= {"sender_key_id": conv["my_key_id"], "recipient_key_id": conv["peer"]["key"]["id"],
             "topic_id": conversation.get("topic_id")} | overrides
    return client.post(f"{API}/chat/conversations/{conv['id']}/messages", headers=headers, json=body)


def _messages(client, headers, conversation_id, **params):
    r = client.get(f"{API}/chat/conversations/{conversation_id}/messages", headers=headers, params=params)
    assert r.status_code == 200, r.text
    return r.json()


def _open(me: Identity, page, message):
    """Decrypt a message from a page, with the peer's key the message names."""
    keys = {k["id"]: k for k in page["keys"]}
    peer_key_id = message["recipient_key_id"] if message["sender_id"] == me.user_id else message["sender_key_id"]
    return decrypt(me, unb64(keys[peer_key_id]["public_key"]), message)


@pytest.fixture
def chat(client):
    """Asha sells a cycle, Ravi wants it; both have set up messaging and Ravi has opened a chat."""
    listing = _listing(client)
    asha, ravi = _setup_keys(client, ASHA), _setup_keys(client, RAVI)
    conversation = _start(client, RAVI, listing["id"])
    return {"listing": listing, "asha": asha, "ravi": ravi, "conv": conversation}


# ------------------------------------------------------------------------------------------ keys
def test_key_setup_backup_and_rotation(client):
    assert client.get(f"{API}/me/chat-key").status_code == 401
    assert client.get(f"{API}/me/chat-key", headers=ASHA).status_code == 404
    asha = _setup_keys(client, ASHA)

    mine = client.get(f"{API}/me/chat-key", headers=ASHA).json()
    restored = Identity.restore(asha.user_id, mine, PASS)          # a second device unlocks the backup
    assert restored.public == asha.public
    with pytest.raises(InvalidTag):
        Identity.restore(asha.user_id, mine, "wrong passphrase")
    with pytest.raises(InvalidTag):                                # a backup only opens for its owner
        Identity.restore(str(uuid.uuid4()), mine, PASS)

    # Others see only the public key, never the backup.
    public = client.get(f"{API}/users/{asha.user_id}/chat-key", headers=RAVI).json()
    assert set(public) == {"id", "user_id", "public_key", "created_at", "is_current"}
    assert unb64(public["public_key"]) == asha.public
    assert client.get(f"{API}/users/{asha.user_id}/chat-key").status_code == 401

    # New passphrase, same key: the key id stays.
    r = client.put(f"{API}/me/chat-key", headers=ASHA, json=asha.key_upload("a new passphrase"))
    assert r.status_code == 200 and r.json()["id"] == mine["id"]
    assert Identity.restore(asha.user_id, r.json(), "a new passphrase").public == asha.public

    # A new key replaces the old one.
    fresh = Identity.generate(asha.user_id)
    r = client.put(f"{API}/me/chat-key", headers=ASHA, json=fresh.key_upload(PASS))
    assert r.status_code == 201 and r.json()["id"] != mine["id"]
    assert client.get(f"{API}/users/{asha.user_id}/chat-key", headers=RAVI).json()["id"] == r.json()["id"]
    assert sql("SELECT count(*) AS n FROM chat_keys WHERE user_id = $1::uuid AND retired_at IS NULL",
               asha.user_id)[0]["n"] == 1


def test_server_held_key(client):
    """No passphrase: the server keeps the plain key and any device just downloads it."""
    asha = Identity.generate(sign_in(client, ASHA))
    r = client.put(f"{API}/me/chat-key", headers=ASHA, json=asha.server_held_upload())
    assert r.status_code == 201
    mine = client.get(f"{API}/me/chat-key", headers=ASHA).json()
    assert mine["backup_kdf"] == "none" and mine["backup_salt"] is None and mine["backup_iterations"] is None
    assert unb64(mine["key_backup"]) == _raw_private(asha.private)

    # An old passphrase backup moves to "none" without changing the key (or its id).
    ravi = _setup_keys(client, RAVI)
    old = client.get(f"{API}/me/chat-key", headers=RAVI).json()
    r = client.put(f"{API}/me/chat-key", headers=RAVI, json=ravi.server_held_upload())
    assert r.status_code == 200 and r.json()["id"] == old["id"] and r.json()["backup_kdf"] == "none"


@pytest.mark.parametrize("change", [
    {"key_backup": b64(b"k" * 31)},
    {"backup_salt": b64(b"s" * 16)},
    {"backup_iterations": 100_000},
])
def test_server_held_key_validation(client, change):
    body = Identity.generate(sign_in(client, ASHA)).server_held_upload() | change
    assert client.put(f"{API}/me/chat-key", headers=ASHA, json=body).status_code == 422


@pytest.mark.parametrize("change", [
    {"public_key": "not base64!"},
    {"public_key": b64(b"x" * 31)},
    {"backup_salt": b64(b"s" * 8)},
    {"backup_iterations": 1000},
    {"backup_kdf": "md5"},
])
def test_key_validation(client, change):
    body = Identity.generate(sign_in(client, ASHA)).key_upload(PASS) | change
    assert client.put(f"{API}/me/chat-key", headers=ASHA, json=body).status_code == 422


# --------------------------------------------------------------------------------- conversations
def test_starting_a_conversation(client):
    listing = _listing(client)
    assert client.post(f"{API}/chat/conversations", json={"listing_id": listing["id"]}).status_code == 401
    r = client.post(f"{API}/chat/conversations", headers=ASHA, json={"listing_id": listing["id"]})
    assert r.status_code == 422                                     # her own listing
    r = client.post(f"{API}/chat/conversations", headers=RAVI, json={"listing_id": str(uuid.uuid4())})
    assert r.status_code == 404

    r = client.post(f"{API}/chat/conversations", headers=RAVI, json={"listing_id": listing["id"]})
    assert r.status_code == 201, r.text
    conv, topic_id = r.json()["conversation"], r.json()["topic_id"]
    assert conv["peer"]["name"] == "Asha"
    [topic] = conv["topics"]
    assert topic["id"] == topic_id and topic["kind"] == "listing" and topic["ref_id"] == listing["id"]
    assert topic["title"] == "Hero cycle" and topic["owner_id"] == conv["peer"]["id"] and topic["status"] == "available"
    # Neither had opened Messages, but the server made both keys, so Ravi can write straight away.
    assert conv["can_send"] is True and conv["peer"]["key"] is not None and conv["my_key_id"] is not None
    assert sql("SELECT count(*) AS n FROM chat_keys WHERE backup_kdf = 'none'")[0]["n"] == 2
    assert [n for n in client.get(f"{API}/me/notifications", headers=ASHA).json()["items"]
            if n["type"] == "chat_message"] == []                    # nothing until a message arrives

    # Opening it again returns the same conversation and topic, and doesn't notify again.
    again = client.post(f"{API}/chat/conversations", headers=RAVI, json={"listing_id": listing["id"]})
    assert again.status_code == 200 and again.json()["conversation"]["id"] == conv["id"]
    assert again.json()["topic_id"] == topic_id
    assert client.get(f"{API}/me/notifications", headers=ASHA).json()["items"] == []

    # The buyer sees the empty chat in their inbox; the seller doesn't until a message arrives.
    assert [c["id"] for c in client.get(f"{API}/chat/conversations", headers=RAVI).json()] == [conv["id"]]
    assert client.get(f"{API}/chat/conversations", headers=ASHA).json() == []

    # Asha's app later finds the key the server made for her and uses it as her own.
    mine = client.get(f"{API}/me/chat-key", headers=ASHA).json()
    assert mine["backup_kdf"] == "none" and mine["id"] == conv["peer"]["key"]["id"]

    client.delete(f"{API}/listings/{listing['id']}", headers=ASHA)
    other = client.post(f"{API}/chat/conversations", headers=MEERA, json={"listing_id": listing["id"]})
    assert other.status_code == 404                                 # removed listings take no new chats
    assert client.get(f"{API}/chat/conversations/{conv['id']}", headers=RAVI).json()["topics"][0]["is_removed"]
    assert client.post(f"{API}/chat/conversations", headers=RAVI, json={}).status_code == 422
    assert client.post(f"{API}/chat/conversations", headers=RAVI,
                       json={"listing_id": listing["id"], "user_id": conv["peer"]["id"]}).status_code == 422


def test_one_chat_per_person_with_topics(client, chat):
    """Two listings from the same seller, a lost report and general chat: one conversation."""
    ravi, asha, conv = chat["ravi"], chat["asha"], chat["conv"]
    lamp = _listing(client, title="Desk lamp", price="400")
    about_lamp = _start(client, RAVI, lamp["id"])
    assert about_lamp["id"] == conv["id"] and about_lamp["topic_id"] != conv["topic_id"]

    from datetime import datetime, timedelta, timezone
    wallet = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "description": "Black leather wallet", "category_id": category(client, ASHA, "lost-found", "Wallet"),
        "occurred_at": (datetime.now(timezone.utc) - timedelta(hours=3)).isoformat()}).json()
    about_wallet = _start(client, RAVI, lost_report_id=wallet["id"])
    general = _start(client, RAVI, user_id=asha.user_id)
    assert about_wallet["id"] == general["id"] == conv["id"] and general["topic_id"] is None

    topics = client.get(f"{API}/chat/conversations/{conv['id']}", headers=RAVI).json()["topics"]
    assert [(t["kind"], t["title"]) for t in topics] == [
        ("listing", "Hero cycle"), ("listing", "Desk lamp"), ("lost_report", "Lost: Wallet")]
    assert topics[2]["description"] == "Black leather wallet" and topics[2]["price"] is None

    _send(client, RAVI, ravi, about_lamp, {"text": "Lamp still there?"})
    _send(client, RAVI, ravi, about_wallet, {"text": "I think I found it"})
    _send(client, RAVI, ravi, general, {"text": "Also, can you help with the DSA assignment?"})
    page = _messages(client, ASHA, conv["id"])
    assert [m["topic_id"] for m in page["items"]] == [about_lamp["topic_id"], about_wallet["topic_id"], None]
    assert [_open(asha, page, m)["text"] for m in page["items"]][-1].startswith("Also")
    assert len(client.get(f"{API}/chat/conversations", headers=ASHA).json()) == 1
    alerts = [n["payload"]["message"] for n in client.get(f"{API}/me/notifications", headers=ASHA).json()["items"]
              if n["type"] == "chat_message"]
    assert alerts == ["Ravi sent you a message about “Desk lamp”"]          # one per unread stretch

    # Offers need one of this chat's listings; a topic from someone else's chat isn't accepted.
    assert _send(client, RAVI, ravi, general, {"amount": "1"}, kind="offer").status_code == 422
    assert _send(client, RAVI, ravi, about_wallet, {"amount": "1"}, kind="offer").status_code == 422
    _setup_keys(client, MEERA)
    meera_chat = _start(client, MEERA, lamp["id"])
    assert _send(client, RAVI, ravi, conv, topic_id=meera_chat["topic_id"]).status_code == 422

    # Offers on two listings are independent, and accepting reserves the right one.
    cycle_offer = _send(client, RAVI, ravi, conv, {"amount": "2000"}, kind="offer").json()
    lamp_offer = _send(client, RAVI, ravi, about_lamp, {"amount": "350"}, kind="offer").json()
    assert sql("SELECT offer_status::text AS s FROM chat_messages WHERE id = $1::uuid",
               cycle_offer["id"])[0]["s"] == "pending"
    client.post(f"{API}/chat/messages/{lamp_offer['id']}/offer", headers=ASHA, json={"action": "accept"})
    assert client.get(f"{API}/listings/{lamp['id']}").json()["status"] == "reserved"
    assert client.get(f"{API}/listings/{chat['listing']['id']}").json()["status"] == "available"

    # Nobody can open a chat about their own report or with themselves.
    assert client.post(f"{API}/chat/conversations", headers=ASHA,
                       json={"lost_report_id": wallet["id"]}).status_code == 422
    assert client.post(f"{API}/chat/conversations", headers=ASHA,
                       json={"user_id": asha.user_id}).status_code == 422


def test_messages_from_before_the_merge_still_open(client, chat):
    """Rev 10 merged per-listing chats; their messages keep the old id as crypto_context_id."""
    ravi, asha, conv = chat["ravi"], chat["asha"], chat["conv"]
    old_id = str(uuid.uuid4())
    body = encrypt(ravi, asha.public, old_id, {"text": "from the old chat"})
    keys = client.get(f"{API}/chat/conversations/{conv['id']}", headers=RAVI).json()
    sql("""INSERT INTO chat_messages (id, conversation_id, crypto_context_id, topic_id, seq, changed_seq, sender_id,
                                      kind, sender_key_id, recipient_key_id, nonce, ciphertext)
           VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 1, 1, $5::uuid, 'text', $6::uuid, $7::uuid, $8, $9)""",
        body["id"], conv["id"], old_id, conv["topic_id"], ravi.user_id, keys["my_key_id"],
        keys["peer"]["key"]["id"], unb64(body["nonce"]), unb64(body["ciphertext"]))
    sql("UPDATE chat_conversations SET last_seq = 1 WHERE id = $1::uuid", conv["id"])
    page = _messages(client, ASHA, conv["id"])
    assert page["items"][0]["crypto_context_id"] == old_id
    assert _open(asha, page, page["items"][0])["text"] == "from the old chat"
    assert _send(client, RAVI, ravi, conv, {"text": "new"}).json()["seq"] == 2


def test_end_to_end_encrypted_round_trip(client, chat):
    ravi, asha, conv = chat["ravi"], chat["asha"], chat["conv"]
    secret = "Hi! Could we meet at the Main Building at 5pm? My number is 98450 12345."
    r = _send(client, RAVI, ravi, conv, {"text": secret})
    assert r.status_code == 201, r.text
    sent = r.json()
    assert sent["seq"] == 1 and sent["kind"] == "text" and sent["sender_id"] == ravi.user_id

    page = _messages(client, ASHA, conv["id"])
    assert [m["id"] for m in page["items"]] == [sent["id"]]
    assert _open(asha, page, page["items"][0])["text"] == secret    # the seller can read it
    assert _open(ravi, _messages(client, RAVI, conv["id"]), sent)["text"] == secret   # and so can the sender

    # The server holds only ciphertext: not the text, and nothing derived from it in plain form.
    row = sql("SELECT * FROM chat_messages WHERE id = $1::uuid", sent["id"])[0]
    assert secret.encode() not in bytes(row["ciphertext"]) and b"98450" not in bytes(row["ciphertext"])
    dump = str([dict(r) for r in sql("SELECT * FROM chat_messages")]) + str(
        [dict(r) for r in sql("SELECT payload FROM notifications")])
    assert "98450" not in dump and "Main Building" not in dump

    # Someone else's key can't open it, even with the right public key of the peer.
    meera = Identity.generate(sign_in(client, MEERA))
    with pytest.raises(InvalidTag):
        decrypt(meera, asha.public, page["items"][0])
    # Tampering is detected: changing the claimed sender, kind or conversation breaks the tag.
    assert page["items"][0]["crypto_context_id"] == conv["id"]
    for field, value in (("sender_id", asha.user_id), ("kind", "offer"), ("crypto_context_id", str(uuid.uuid4()))):
        with pytest.raises(InvalidTag):
            _open(asha, page, page["items"][0] | {field: value})

    # Both phones show the same safety number to compare in person.
    assert safety_number(ravi.user_id, ravi.public, asha.user_id, asha.public) == \
        safety_number(asha.user_id, asha.public, ravi.user_id, ravi.public)


def test_only_the_two_people_can_see_or_touch_a_conversation(client, chat):
    conv = chat["conv"]
    message = _send(client, RAVI, chat["ravi"], conv).json()
    offer = _send(client, RAVI, chat["ravi"], conv, {"amount": "2000"}, kind="offer").json()
    make_admin(client, ADMIN)
    meera = _setup_keys(client, MEERA)

    for outsider in (MEERA, ADMIN, KIRAN):
        assert client.get(f"{API}/chat/conversations/{conv['id']}", headers=outsider).status_code == 404
        r = client.get(f"{API}/chat/conversations/{conv['id']}/messages", headers=outsider)
        assert r.status_code == 404
        assert client.post(f"{API}/chat/conversations/{conv['id']}/read", headers=outsider,
                           json={"seq": 5}).status_code == 404
        assert client.post(f"{API}/chat/messages/{offer['id']}/offer", headers=outsider,
                           json={"action": "accept"}).status_code == 404
        assert client.delete(f"{API}/chat/messages/{message['id']}", headers=outsider).status_code == 404
        assert client.get(f"{API}/chat/conversations", headers=outsider).json() == []
        assert client.get(f"{API}/chat/unread", headers=outsider).json()["unread_messages"] == 0
    for guest_call in (client.get(f"{API}/chat/conversations"),
                       client.get(f"{API}/chat/conversations/{conv['id']}/messages")):
        assert guest_call.status_code == 401

    # An outsider can't write into it either, even with a well-formed message.
    body = encrypt(meera, chat["asha"].public, conv["id"], {"text": "hi"})
    body |= {"sender_key_id": client.get(f"{API}/me/chat-key", headers=MEERA).json()["id"],
             "recipient_key_id": conv["peer"]["key"]["id"] if conv["peer"]["key"] else str(uuid.uuid4())}
    r = client.post(f"{API}/chat/conversations/{conv['id']}/messages", headers=MEERA, json=body)
    assert r.status_code == 404
    assert sql("SELECT count(*) AS n FROM chat_messages")[0]["n"] == 2
    assert offer["offer_status"] == "pending"


def test_messages_must_use_current_keys_and_ids_are_idempotent(client, chat):
    ravi, conv = chat["ravi"], chat["conv"]
    first = _send(client, RAVI, ravi, conv, {"text": "hello"})
    assert first.status_code == 201
    stale = client.get(f"{API}/chat/conversations/{conv['id']}", headers=RAVI).json()

    # Retrying the exact same message (e.g. after a timeout) returns it instead of a duplicate.
    body = encrypt(ravi, unb64(stale["peer"]["key"]["public_key"]), conv["id"], {"text": "again"})
    body |= {"sender_key_id": stale["my_key_id"], "recipient_key_id": stale["peer"]["key"]["id"]}
    url = f"{API}/chat/conversations/{conv['id']}/messages"
    assert client.post(url, headers=RAVI, json=body).status_code == 201
    retry = client.post(url, headers=RAVI, json=body)
    assert retry.status_code == 200 and retry.json()["seq"] == 2
    reused = client.post(url, headers=RAVI, json=body | {"ciphertext": b64(b"z" * 40)})
    assert reused.status_code == 409
    assert client.post(url, headers=ASHA, json=body).status_code == 409   # someone else's id

    # Asha gets a new key (new phone, forgot passphrase): Ravi's app must re-encrypt to it.
    new_asha = Identity.generate(chat["asha"].user_id)
    client.put(f"{API}/me/chat-key", headers=ASHA, json=new_asha.key_upload(PASS))
    body = encrypt(ravi, chat["asha"].public, conv["id"], {"text": "to the old key"})
    body |= {"sender_key_id": stale["my_key_id"], "recipient_key_id": stale["peer"]["key"]["id"]}
    r = client.post(url, headers=RAVI, json=body)
    assert r.status_code == 409 and "key has changed" in r.json()["detail"]
    assert _send(client, RAVI, ravi, conv, {"text": "to the new key"}).status_code == 201
    page = _messages(client, ASHA, conv["id"])
    assert _open(new_asha, page, page["items"][-1])["text"] == "to the new key"
    with pytest.raises(InvalidTag):                                  # the old messages need the old key
        _open(new_asha, page, page["items"][0])
    assert {k["is_current"] for k in page["keys"] if k["user_id"] == new_asha.user_id} == {True, False}


@pytest.mark.parametrize("change", [
    {"nonce": b64(b"n" * 8)},
    {"ciphertext": b64(b"c" * 10)},
    {"ciphertext": "%%%"},
    {"kind": "image"},
    {"id": "not-a-uuid"},
])
def test_message_validation(client, chat, change):
    assert _send(client, RAVI, chat["ravi"], chat["conv"], **change).status_code == 422


def test_sync_reads_and_unread_counts(client, chat):
    ravi, asha, conv = chat["ravi"], chat["asha"], chat["conv"]
    for text in ("one", "two", "three"):
        _send(client, RAVI, ravi, conv, {"text": text})
    assert client.get(f"{API}/chat/unread", headers=ASHA).json() == {"unread_messages": 3, "conversations": 1}
    assert client.get(f"{API}/chat/unread", headers=RAVI).json()["unread_messages"] == 0   # own messages
    # One notification for the unread stretch, not one per message; it never contains the text.
    alerts = [n for n in client.get(f"{API}/me/notifications", headers=ASHA).json()["items"]
              if n["type"] == "chat_message"]
    assert len(alerts) == 1 and alerts[0]["payload"]["message"] == "Ravi sent you a message about “Hero cycle”"

    inbox = client.get(f"{API}/chat/conversations", headers=ASHA).json()
    assert inbox[0]["unread_count"] == 3 and inbox[0]["peer"]["name"] == "Ravi"
    assert _open(asha, {"keys": [inbox[0]["peer"]["key"]]}, inbox[0]["last_message"])["text"] == "three"

    page = _messages(client, ASHA, conv["id"], limit=2)              # latest page, then older history
    assert [m["seq"] for m in page["items"]] == [2, 3] and page["has_more"]
    older = _messages(client, ASHA, conv["id"], before=2)
    assert [m["seq"] for m in older["items"]] == [1] and not older["has_more"]
    assert client.get(f"{API}/chat/conversations/{conv['id']}/messages", headers=ASHA,
                      params={"after": 1, "before": 2}).status_code == 422

    r = client.post(f"{API}/chat/conversations/{conv['id']}/read", headers=ASHA, json={"seq": 99})
    assert r.json() == {"my_last_read_seq": 3}                       # capped at what exists
    assert client.post(f"{API}/chat/conversations/{conv['id']}/read", headers=ASHA,
                       json={"seq": 1}).json() == {"my_last_read_seq": 3}   # never goes back
    assert client.get(f"{API}/chat/conversations/{conv['id']}", headers=RAVI).json()["peer_last_read_seq"] == 3
    assert client.get(f"{API}/chat/unread", headers=ASHA).json()["unread_messages"] == 0

    # After reading, the next message notifies again. Replying marks the replier's side read.
    _send(client, RAVI, ravi, conv, {"text": "four"})
    _send(client, ASHA, asha, conv, {"text": "Yes, still available"})
    assert len([n for n in client.get(f"{API}/me/notifications", headers=ASHA).json()["items"]
                if n["type"] == "chat_message"]) == 2
    assert client.get(f"{API}/chat/unread", headers=ASHA).json()["unread_messages"] == 0

    # Sync: only what changed after what the client has seen.
    changes = _messages(client, RAVI, conv["id"], after=4)
    assert [m["seq"] for m in changes["items"]] == [5]
    assert _open(ravi, changes, changes["items"][0])["text"] == "Yes, still available"


def test_offers(client, chat):
    ravi, asha, conv = chat["ravi"], chat["asha"], chat["conv"]
    offer = _send(client, RAVI, ravi, conv, {"amount": "2000", "note": "cash today"}, kind="offer").json()
    assert offer["offer_status"] == "pending"
    page = _messages(client, ASHA, conv["id"])
    assert _open(asha, page, page["items"][0]) == {"v": 1, "type": "offer", "amount": "2000", "note": "cash today"}
    alerts = [n["payload"]["message"] for n in client.get(f"{API}/me/notifications", headers=ASHA).json()["items"]]
    assert alerts == ["Ravi made you an offer on “Hero cycle”"]

    url = f"{API}/chat/messages/{offer['id']}/offer"
    assert client.post(url, headers=RAVI, json={"action": "accept"}).status_code == 403    # not your own
    assert client.post(url, headers=ASHA, json={"action": "withdraw"}).status_code == 403  # not hers

    # Asha counters: Ravi's offer is superseded (and shows up as a change when syncing).
    counter = _send(client, ASHA, asha, conv, {"amount": "2300"}, kind="offer").json()
    changes = _messages(client, RAVI, conv["id"], after=offer["changed_seq"])
    assert {m["id"]: m["offer_status"] for m in changes["items"]} == {offer["id"]: "superseded",
                                                                      counter["id"]: "pending"}
    assert client.post(url, headers=ASHA, json={"action": "decline"}).status_code == 409   # no longer open

    accepted = client.post(f"{API}/chat/messages/{counter['id']}/offer", headers=RAVI, json={"action": "accept"})
    assert accepted.status_code == 200 and accepted.json()["offer_status"] == "accepted"
    listing = client.get(f"{API}/listings/{chat['listing']['id']}").json()
    assert listing["status"] == "reserved"                           # held for the buyer
    assert accepted.json()["changed_seq"] > counter["changed_seq"]
    assert client.get(f"{API}/me/notifications", headers=ASHA).json()["items"][0]["payload"]["message"] == \
        "Ravi accepted your offer on “Hero cycle”"

    # Withdraw and decline.
    third = _send(client, RAVI, ravi, conv, {"amount": "2200"}, kind="offer").json()
    assert client.post(f"{API}/chat/messages/{third['id']}/offer", headers=RAVI,
                       json={"action": "withdraw"}).json()["offer_status"] == "withdrawn"
    fourth = _send(client, RAVI, ravi, conv, {"amount": "2250"}, kind="offer").json()
    assert client.post(f"{API}/chat/messages/{fourth['id']}/offer", headers=ASHA,
                       json={"action": "decline"}).json()["offer_status"] == "declined"
    text = _send(client, RAVI, ravi, conv).json()
    assert client.post(f"{API}/chat/messages/{text['id']}/offer", headers=ASHA,
                       json={"action": "accept"}).status_code == 422

    # Accepting while reserved keeps it reserved.
    client.patch(f"{API}/listings/{chat['listing']['id']}/status", headers=ASHA, json={"status": "available"})
    declined_listing = client.get(f"{API}/listings/{chat['listing']['id']}").json()
    assert declined_listing["status"] == "available"                 # declining never reserves

    # Sold: no new offers, and an open one can't be accepted.
    fifth = _send(client, RAVI, ravi, conv, {"amount": "2400"}, kind="offer").json()
    client.patch(f"{API}/listings/{chat['listing']['id']}/status", headers=ASHA, json={"status": "sold"})
    assert _send(client, RAVI, ravi, conv, {"amount": "2450"}, kind="offer").status_code == 422
    assert client.post(f"{API}/chat/messages/{fifth['id']}/offer", headers=ASHA,
                       json={"action": "accept"}).status_code == 409
    assert _send(client, RAVI, ravi, conv, {"text": "Ah, never mind"}).status_code == 201   # chatting still works


def test_unsend_erases_the_ciphertext(client, chat):
    ravi, conv = chat["ravi"], chat["conv"]
    message = _send(client, RAVI, ravi, conv, {"text": "oops, wrong chat"}).json()
    offer = _send(client, RAVI, ravi, conv, {"amount": "1"}, kind="offer").json()
    assert client.delete(f"{API}/chat/messages/{message['id']}", headers=ASHA).status_code == 403
    assert client.delete(f"{API}/chat/messages/{message['id']}", headers=RAVI).status_code == 204
    assert client.delete(f"{API}/chat/messages/{message['id']}", headers=RAVI).status_code == 204   # idempotent
    assert client.delete(f"{API}/chat/messages/{offer['id']}", headers=RAVI).status_code == 204

    row = sql("SELECT nonce, ciphertext, deleted_at FROM chat_messages WHERE id = $1::uuid", message["id"])[0]
    assert row["nonce"] is None and row["ciphertext"] is None and row["deleted_at"] is not None
    changes = _messages(client, ASHA, conv["id"], after=offer["changed_seq"])
    gone = {m["id"]: m for m in changes["items"]}
    assert gone[message["id"]]["ciphertext"] is None and gone[offer["id"]]["offer_status"] == "withdrawn"
    assert client.get(f"{API}/chat/unread", headers=ASHA).json()["unread_messages"] == 0


def test_blocking(client, chat):
    ravi, asha, conv = chat["ravi"], chat["asha"], chat["conv"]
    assert client.put(f"{API}/chat/blocks/{asha.user_id}", headers=ASHA).status_code == 422   # yourself
    assert client.put(f"{API}/chat/blocks/{uuid.uuid4()}", headers=ASHA).status_code == 404
    assert client.put(f"{API}/chat/blocks/{ravi.user_id}", headers=ASHA).status_code == 204
    assert client.put(f"{API}/chat/blocks/{ravi.user_id}", headers=ASHA).status_code == 204   # idempotent
    assert client.get(f"{API}/chat/blocks", headers=ASHA).json() == [{"id": ravi.user_id, "name": "Ravi"}]

    r = _send(client, RAVI, ravi, conv)
    assert r.status_code == 403 and r.json()["detail"] == "You can't send messages in this conversation."
    view = client.get(f"{API}/chat/conversations/{conv['id']}", headers=RAVI).json()
    assert view["can_send"] is False and "block" not in view["cant_send_reason"].lower()   # not told why
    mine = client.get(f"{API}/chat/conversations/{conv['id']}", headers=ASHA).json()
    assert mine["blocked_by_me"] and "Unblock" in mine["cant_send_reason"]
    assert _send(client, ASHA, asha, conv).status_code == 403
    other = _listing(client, title="Lamp", price="300")
    assert client.post(f"{API}/chat/conversations", headers=RAVI, json={"listing_id": other["id"]}).status_code == 403

    assert client.delete(f"{API}/chat/blocks/{ravi.user_id}", headers=ASHA).status_code == 204
    assert _send(client, RAVI, ravi, conv).status_code == 201
    assert client.get(f"{API}/chat/blocks", headers=ASHA).json() == []


def test_deactivated_peer_and_rate_limit(client, chat, monkeypatch):
    ravi, conv = chat["ravi"], chat["conv"]
    from app.routers import chat as chat_router
    monkeypatch.setattr(chat_router, "MAX_MESSAGES_PER_MINUTE", 3)
    for _ in range(3):
        assert _send(client, RAVI, ravi, conv).status_code == 201
    assert _send(client, RAVI, ravi, conv).status_code == 429

    sql("UPDATE users SET is_active = false WHERE id = $1::uuid", chat["asha"].user_id)
    sql("DELETE FROM chat_messages")
    r = _send(client, RAVI, ravi, conv)
    assert r.status_code == 403 and "deactivated" in r.json()["detail"]
