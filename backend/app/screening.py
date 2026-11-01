"""Automatic flagging of new posts (future plan §1.6).

Every new or edited Buy & Sell listing and Lost & Found report is checked, and anything that
looks wrong is filed as a report in the normal moderation queue (reports.source = 'system', no
reporter), so moderators see automatic and student reports in one place. Nothing is deleted
automatically; a moderator decides, and a confirmed removal of a listing is a seller-trust strike
like any other (app/seller_trust.py).

The checks:
- Prohibited item (listings): the title and description are compared, with bge-small-en-v1.5 (the
  category-suggestion model, already in the API), against short descriptions of what can't be
  sold on campus (drugs, alcohol, tobacco, weapons, fake documents, leaked papers, counterfeits,
  stolen goods, fireworks, "I'll write your exam") AND against harmless look-alikes (water
  bottles, toy guns, kitchen knives, beer mugs, previous-year papers...). It flags when the best
  prohibited match is close and beats the best harmless one. A short list of unambiguous words
  (ganja, MDMA, vodka, pistol...) flags on its own. A prohibited-item flag also HOLDS the listing
  (hidden from everyone but the seller and moderators) until a moderator decides: a few hours of
  a legitimate listing being hidden costs much less than an illegal one staying up.
  Calibrated 2 Nov 2026 on 19 illegal and ~150 ordinary titles: 15/19 caught by similarity alone,
  the rest by the word list; no ordinary title flagged.
- Gibberish title/description: keyboard runs (asdf, qwer), the same letter three times, five
  consonants in a row, or mostly non-words. The "dictionary" is the 21,700 whole words in the bge
  tokenizer's vocabulary, so no extra file. Pronounceable unknown words (brands, names) pass.
- Spam: the same person posting a near-identical title for the third time in 24 hours, or more
  than 8 posts in an hour.
- Obscene photo: done after the response by app/matching (needs the image model; see
  app/matching/nsfw.py), which calls flag() the same way.
Gibberish, spam and photo flags leave the post visible until a moderator acts.
"""
import json
import logging
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from uuid import UUID

import asyncpg
from fastapi import BackgroundTasks

from .categories_suggest import QUERY_PREFIX, TOKENIZER_FILE, get_embedder, suggestion_available
from .config import get_settings
from .matching.trigger import model_dir
from .notify import create_notifications, deliver_push

log = logging.getLogger("campushub.screening")

PROHIBITED = [
    "drugs for sale", "weed, ganja, marijuana, cannabis", "cocaine, MDMA, LSD, ecstasy pills",
    "hash, charas, hashish", "prescription painkillers or sleeping pills without prescription",
    "codeine cough syrup, tramadol", "alcohol for sale: beer, whisky, vodka, rum, liquor bottles",
    "cigarettes, vapes, e-cigarettes, tobacco, gutka", "real gun, pistol, revolver, firearm, bullets",
    "combat knife, dagger, sword, weapon", "fake ID card, forged documents, fake certificates",
    "leaked exam question papers, answer keys for sale", "counterfeit branded goods, replica watches, first copy",
    "stolen goods, phone without bill", "fireworks, explosives, firecrackers",
    "assignment writing service, will write your exam for you",
]
HARMLESS = [
    "water bottle, flask, sipper", "toy, kids toy, toy gun", "kitchen utensils, knife set, cutlery", "mug, glass, cup",
    "study notes, previous year papers, books", "artificial plant decor", "multitool, tools", "watch, wristwatch",
    "phone with bill and box", "medicine box, first aid kit", "stationery, pens, paper",
] + [f"a {c} item for sale" for c in ("books", "electronics", "cycles", "furniture", "clothing",
                                       "kitchen & appliances", "sports & fitness", "plant")]
PROHIBITED_WORDS = re.compile(
    r"\b(ganja|weed|cannabis|marijuana|charas|hashish|mdma|cocaine|lsd|ecstasy|heroin|meth|codeine|tramadol|"
    r"vodka|whisky|whiskey|rum|liquor|alcohol|cigarettes?|vapes?|gutka|pistol|revolver|firearms?|ammunition|"
    r"bullets?|counterfeit|forged)\b", re.IGNORECASE)
PROHIBITED_AT = 0.60       # closest prohibited description, cosine
PROHIBITED_LEAD = 0.0      # ... and at least this much above the closest harmless one
SPAM_REPEATS = 2           # earlier near-identical posts in 24 h that make this one spam
SPAM_PER_HOUR = 8
SPAM_SIMILAR = 0.93

_KEYBOARD_RUN = re.compile(r"(asdf|sdfg|dfgh|fghj|ghjk|hjkl|qwer|wert|erty|rtyu|tyui|yuio|zxcv|xcvb|cvbn|vbnm)")


@dataclass(frozen=True)
class Target:
    kind: str          # report target_type: listing, lost_report, found_report
    module: str
    table: str
    owner: str         # owner column
    text_sql: str      # what to check
    noun: str


TARGETS = {
    "listing": Target("listing", "buy_sell", "listings", "seller_id",
                      "title || E'\\n' || coalesce(description, '')", "listing"),
    "lost_report": Target("lost_report", "lost_found", "lost_reports", "reporter_id", "description", "lost item report"),
    "found_report": Target("found_report", "lost_found", "found_reports", "reporter_id", "description", "found item report"),
}


@lru_cache
def _vocabulary() -> frozenset[str]:
    path = Path(model_dir()) / TOKENIZER_FILE
    try:
        vocab = json.loads(path.read_text())["model"]["vocab"]
    except (OSError, KeyError, ValueError):
        return frozenset()
    return frozenset(w for w in vocab if w.isalpha() and len(w) >= 2)


def _word_ok(word: str, vocab: frozenset[str]) -> bool:
    if word in vocab:
        return True
    if re.search(r"(.)\1\1", word) or re.search(r"[bcdfghjklmnpqrstvwxz]{5,}", word):
        return False
    return bool(re.search(r"[aeiouy]", word))   # a pronounceable unknown word: a brand or a name


def is_gibberish(text: str) -> bool:
    lowered = text.lower()
    if _KEYBOARD_RUN.search(re.sub(r"[^a-z]", "", lowered)):
        return True
    words = [w for w in re.findall(r"[a-z]+", lowered) if len(w) >= 3]
    if not words:
        return not re.search(r"[a-z0-9]", lowered)
    vocab = _vocabulary()
    bad = [w for w in words if not _word_ok(w, vocab)]
    return len(bad) / len(words) >= 0.5


def prohibited_reason(text: str) -> str | None:
    """Why this looks like a prohibited item, or None."""
    word = PROHIBITED_WORDS.search(text)
    if word:
        return f'mentions "{word.group(0).lower()}"'
    if not suggestion_available():
        return None
    emb = get_embedder()
    vec = emb.embed([QUERY_PREFIX + text[:500]])[0]
    bad = emb.embed(PROHIBITED) @ vec
    good = emb.embed(HARMLESS) @ vec
    best = int(bad.argmax())
    if bad[best] >= PROHIBITED_AT and bad[best] - good.max() >= PROHIBITED_LEAD:
        return f"looks like: {PROHIBITED[best]}"
    return None


async def _spam_reason(conn: asyncpg.Connection, t: Target, item_id: UUID, owner_id: UUID,
                       text: str) -> str | None:
    rows = await conn.fetch(
        f"""SELECT id, {t.text_sql} AS text, created_at > now() - interval '1 hour' AS last_hour
            FROM {t.table} WHERE {t.owner} = $1 AND id <> $2 AND deleted_at IS NULL
              AND created_at > now() - interval '24 hours'""", owner_id, item_id)
    if sum(r["last_hour"] for r in rows) + 1 > SPAM_PER_HOUR:
        return f"more than {SPAM_PER_HOUR} posts in an hour"
    if len(rows) < SPAM_REPEATS:
        return None
    norm = " ".join(re.findall(r"[a-z0-9]+", text.lower()))
    same = [r for r in rows if " ".join(re.findall(r"[a-z0-9]+", r["text"].lower())) == norm]
    if len(same) < SPAM_REPEATS and suggestion_available():
        emb = get_embedder()
        sims = emb.embed([r["text"][:300] for r in rows]) @ emb.embed([text[:300]])[0]
        same = [r for r, s in zip(rows, sims) if s >= SPAM_SIMILAR]
    if len(same) >= SPAM_REPEATS:
        return f"posted {len(same) + 1} near-identical times in 24 hours"
    return None


async def flag(conn: asyncpg.Connection, background: BackgroundTasks | None, kind: str, item_id: UUID,
               reasons: list[str], hold: bool = False) -> bool:
    """File (or add to) the open automatic report on this item. Returns True if anything new."""
    t = TARGETS[kind]
    item = await conn.fetchrow(
        f"SELECT {t.owner} AS owner_id, {t.text_sql} AS text FROM {t.table} WHERE id = $1 AND deleted_at IS NULL",
        item_id)
    if item is None or not reasons:
        return False
    existing = await conn.fetchrow(
        "SELECT id, reason FROM reports WHERE target_type = $1 AND target_id = $2 AND status = 'open' "
        "AND source = 'system' FOR UPDATE", kind, item_id)
    new = [r for r in reasons if not existing or r not in existing["reason"]]
    if not new:
        return False
    if existing:
        await conn.execute("UPDATE reports SET reason = left(reason || '; ' || $2, 1000) WHERE id = $1",
                           existing["id"], "; ".join(new))
    else:
        column = f"{kind}_id"
        await conn.execute(
            f"""INSERT INTO reports (source, module, target_type, {column}, reason)
                VALUES ('system', $1, $2, $3, left($4, 1000))""",
            t.module, kind, item_id, "Automatic flag: " + "; ".join(new))
    held = False
    if hold and kind == "listing":
        held = await conn.fetchval(
            "UPDATE listings SET held_for_review_at = now() WHERE id = $1 AND held_for_review_at IS NULL "
            "RETURNING true", item_id) or False
    title = " ".join(item["text"].split())
    title = title if len(title) <= 60 else title[:59].rstrip() + "…"
    if held:
        message = (f'Your listing "{title}" is hidden until a moderator reviews it: it was flagged '
                   "automatically as a possible prohibited item. If it's fine, it will be back shortly.")
    elif not existing:
        message = (f'Your {t.noun} "{title}" was flagged automatically for a moderator to review. It stays '
                   "up meanwhile; you'll be told what they decide.")
    else:
        return True
    payload = {"message": message, "target_type": kind, "target_id": str(item_id)}
    await create_notifications(conn, [item["owner_id"]], "moderation_action", payload)
    if background is not None:
        background.add_task(deliver_push, [item["owner_id"]], "moderation_action", payload)
    return True


async def screen_text(conn: asyncpg.Connection, background: BackgroundTasks | None, kind: str,
                      item_id: UUID) -> bool:
    """Run the text checks on a new or edited post. Returns True if the post is held back."""
    if not get_settings().auto_flag:
        return False
    t = TARGETS[kind]
    item = await conn.fetchrow(
        f"SELECT {t.owner} AS owner_id, {t.text_sql} AS text FROM {t.table} WHERE id = $1", item_id)
    if item is None:
        return False
    text = item["text"].strip()
    reasons, hold = [], False
    try:
        if kind == "listing" and (why := prohibited_reason(text)):
            reasons.append(f"possible prohibited item ({why})")
            hold = True
    except Exception:  # noqa: BLE001 - a broken model must never block posting
        log.exception("Prohibited-item check failed for %s %s", kind, item_id)
    headline = text.split("\n", 1)[0]
    if is_gibberish(headline):
        reasons.append("gibberish title" if kind == "listing" else "gibberish description")
    if spam := await _spam_reason(conn, t, item_id, item["owner_id"], text):
        reasons.append(f"possible spam ({spam})")
    if reasons:
        await flag(conn, background, kind, item_id, reasons, hold=hold)
    return hold
