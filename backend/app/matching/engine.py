"""Score lost/found report pairs by description and photo, store the likely ones, alert owners.

match_report(kind, id) runs whenever a report is filed, edited, gets new photos or reopens:

1. Embed what's new: the description (MiniLM for text-text, MobileCLIP text for text-photo) and
   each photo not embedded yet (MobileCLIP image). Vectors of removed photos are dropped.
2. Candidates: open reports of the other kind, by someone else, with a compatible time (lost no
   later than a day after it was found). Any category: a mis-filed category no longer hides a
   match. Candidates without vectors (filed before matching existed) are embedded on the spot.
3. Three similarities per pair: description vs description, best photo vs photo, and best
   description vs the other report's photo. Each is scaled to 0-1 over its calibrated range
   (SIGNALS) and combined so agreeing signals reinforce each other: 1 - prod(1 - s). The same
   category adds CATEGORY_BONUS.
4. Pairs scoring >= match_possible are kept in lf_matches (shown on the owner's report). A pair
   >= match_strong alerts the lost report's owner once per found report, in either direction (a
   new found report, or a new lost report that matches an older found one).
5. matched_rev is set only if the report didn't change meanwhile; otherwise the run for the
   newer revision finishes the job.

The ranges come from scripts/calibrate_matching.py (description pairs, look-alike items, and
photos of everyday lost items). Text-photo similarity is weak on its own (CLIP scores sit around
0.1-0.35), so it is capped at 0.6: it can only make a strong match together with another signal.
"""
import asyncio
import hashlib
import logging
from dataclasses import dataclass, field
from uuid import UUID

import asyncpg
import numpy as np

from ..config import get_settings
from ..db import get_pool
from ..lf_kinds import FOUND, KINDS, LOST, Kind, other_kind
from ..notify import create_notifications, deliver_push
from ..storage import s3_client
from .models import CLIP_IMAGE_MODEL, CLIP_TEXT_MODEL, TEXT_MODEL, Embedder

log = logging.getLogger("campushub.matching")

MAX_CANDIDATES = 500   # newest open reports of the other kind; campus volume is far below this


@dataclass(frozen=True)
class Signal:
    lo: float          # similarity that counts as no evidence
    hi: float          # similarity that counts as full evidence
    cap: float = 1.0   # most this signal can contribute on its own

    def scale(self, similarity: float | None) -> float:
        if similarity is None:
            return 0.0
        return min(self.cap, max(0.0, (similarity - self.lo) / (self.hi - self.lo)))


# Calibration (1 Nov 2026, scripts/calibrate_matching.py), cosine similarity:
#   description pairs about the same item: median 0.69 (0.48-0.81); unrelated items: median 0.19;
#   look-alike items (two different wallets): median 0.56.
#   photo of the same item re-shot: median 0.94 (0.76-0.98); different kinds of item: max 0.55.
#   description vs a photo of that kind of item: median 0.22; of another kind: median 0.08.
# With descriptions alone this alerts 14/20 true pairs (the other 6 are listed as possible) and
# 1/8 look-alikes; 1 of 364 unrelated pairs is listed, none alert. Photos add evidence on top.
SIGNALS = {
    "text": Signal(0.33, 0.80),
    "photo": Signal(0.55, 0.90),
    "cross": Signal(0.18, 0.32, cap=0.6),
}
REASONS = {"text": "Similar description", "photo": "Similar photo", "cross": "Photo fits the description"}
REASON_AT = 0.4
CATEGORY_BONUS = 0.1


def score_pair(text: float | None, photo: float | None, cross: float | None,
               same_category: bool) -> tuple[float, list[str]]:
    """Combined 0-1 score and the reasons to show for it."""
    parts = {"text": SIGNALS["text"].scale(text), "photo": SIGNALS["photo"].scale(photo),
             "cross": SIGNALS["cross"].scale(cross)}
    miss = 1.0
    for p in parts.values():
        miss *= 1.0 - p
    score = min(1.0, 1.0 - miss + (CATEGORY_BONUS if same_category else 0.0))
    reasons = [REASONS[k] for k, p in parts.items() if p >= REASON_AT]
    if same_category:
        reasons.append("Same category")
    return round(score, 4), reasons


@dataclass
class Vectors:
    text: np.ndarray | None = None
    clip_text: np.ndarray | None = None
    photos: list[np.ndarray] = field(default_factory=list)


def similarities(a: Vectors, b: Vectors) -> tuple[float | None, float | None, float | None]:
    text = float(a.text @ b.text) if a.text is not None and b.text is not None else None
    photo = max((float(x @ y) for x in a.photos for y in b.photos), default=None)
    cross = [float(a.clip_text @ y) for y in b.photos if a.clip_text is not None]
    cross += [float(b.clip_text @ x) for x in a.photos if b.clip_text is not None]
    return text, photo, max(cross, default=None)


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


async def _fetch_photo(key: str) -> bytes | None:
    s = get_settings()

    def get() -> bytes:
        return s3_client().get_object(Bucket=s.s3_bucket, Key=key)["Body"].read()
    try:
        return await asyncio.to_thread(get)
    except Exception:  # noqa: BLE001 - retried on the next run
        log.warning("Could not fetch photo %s for matching", key, exc_info=True)
        return None


async def ensure_vectors(conn: asyncpg.Connection, kind: Kind, reports: list[asyncpg.Record],
                         embedder: Embedder) -> None:
    """Embed descriptions that are new or edited and photos not seen yet; drop removed photos."""
    if not reports:
        return
    ids = [r["id"] for r in reports]
    fk = kind.photo_fk
    have = {(r["rid"], r["model"], r["s3_key"]): r["source_hash"] for r in await conn.fetch(
        f"SELECT {fk} AS rid, model, s3_key, source_hash FROM lf_embeddings WHERE {fk} = ANY($1::uuid[])", ids)}
    photos: dict[UUID, list[str]] = {}
    for p in await conn.fetch(
            f"SELECT {fk} AS rid, s3_key FROM {kind.photos} WHERE {fk} = ANY($1::uuid[]) ORDER BY sort_order", ids):
        photos.setdefault(p["rid"], []).append(p["s3_key"])

    rows = []   # (report id, model, s3_key, source_hash, vector)
    for r in reports:
        digest = _hash(r["description"])
        for model, embed in ((TEXT_MODEL, embedder.text), (CLIP_TEXT_MODEL, embedder.clip_text)):
            if have.get((r["id"], model, None)) != digest:
                rows.append((r["id"], model, None, digest, await asyncio.to_thread(embed, r["description"])))
        for key in photos.get(r["id"], []):
            if (r["id"], CLIP_IMAGE_MODEL, key) in have:
                continue
            data = await _fetch_photo(key)
            if data is None:
                continue
            vec = await asyncio.to_thread(embedder.image, data)
            # An unreadable file is stored as an empty vector so it isn't fetched again.
            rows.append((r["id"], CLIP_IMAGE_MODEL, key, _hash(key), vec or []))

    await conn.execute(
        f"""DELETE FROM lf_embeddings e WHERE e.{fk} = ANY($1::uuid[]) AND e.s3_key IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM {kind.photos} p WHERE p.{fk} = e.{fk} AND p.s3_key = e.s3_key)""", ids)
    if rows:
        await conn.executemany(
            f"""INSERT INTO lf_embeddings ({fk}, model, s3_key, source_hash, vec) VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT ((COALESCE(lost_report_id, found_report_id)), model, (COALESCE(s3_key, '')))
                DO UPDATE SET source_hash = EXCLUDED.source_hash, vec = EXCLUDED.vec, created_at = now()""",
            rows)


async def load_vectors(conn: asyncpg.Connection, kind: Kind, ids: list[UUID]) -> dict[UUID, Vectors]:
    out: dict[UUID, Vectors] = {i: Vectors() for i in ids}
    for r in await conn.fetch(
            f"SELECT {kind.photo_fk} AS rid, model, vec FROM lf_embeddings WHERE {kind.photo_fk} = ANY($1::uuid[])",
            ids):
        if not r["vec"]:
            continue
        v = np.asarray(r["vec"], dtype=np.float32)
        if r["model"] == TEXT_MODEL:
            out[r["rid"]].text = v
        elif r["model"] == CLIP_TEXT_MODEL:
            out[r["rid"]].clip_text = v
        elif r["model"] == CLIP_IMAGE_MODEL:
            out[r["rid"]].photos.append(v)
    return out


Push = tuple[list[UUID], dict]


async def match_report(conn: asyncpg.Connection, kind: Kind, report_id: UUID, embedder: Embedder) -> list[Push]:
    """Recompute this report's matches. Returns the pushes to deliver for new strong matches."""
    me = await conn.fetchrow(
        f"""SELECT id, reporter_id, description, category_id, {kind.when} AS at, status::text AS status,
                   deleted_at, match_rev FROM {kind.table} WHERE id = $1""", report_id)
    if me is None:
        return []
    if me["deleted_at"] is not None or me["status"] != "open":
        # Nothing to match; its stored pairs are hidden while it's closed and refreshed on reopening.
        await conn.execute(f"UPDATE {kind.table} SET matched_rev = $2 WHERE id = $1 AND match_rev = $2",
                           report_id, me["match_rev"])
        return []

    other = other_kind(kind)
    # Compatible times, with a day's grace for rough guesses: lost_at <= found_at + 1 day.
    time_rule = (f"c.{other.when} >= $2::timestamptz - interval '1 day'" if kind is LOST
                 else f"c.{other.when} <= $2::timestamptz + interval '1 day'")
    candidates = await conn.fetch(
        f"""SELECT c.id, c.description, c.category_id FROM {other.table} c
            WHERE c.status = 'open' AND c.deleted_at IS NULL AND c.reporter_id <> $1 AND {time_rule}
            ORDER BY c.created_at DESC LIMIT {MAX_CANDIDATES}""", me["reporter_id"], me["at"])

    await ensure_vectors(conn, kind, [me], embedder)
    await ensure_vectors(conn, other, list(candidates), embedder)
    mine = (await load_vectors(conn, kind, [report_id]))[report_id]
    theirs = await load_vectors(conn, other, [c["id"] for c in candidates])

    settings = get_settings()
    kept = []
    for c in candidates:
        text, photo, cross = similarities(mine, theirs[c["id"]])
        score, reasons = score_pair(text, photo, cross, c["category_id"] == me["category_id"])
        if score >= settings.match_possible:
            lost_id, found_id = (report_id, c["id"]) if kind is LOST else (c["id"], report_id)
            kept.append((lost_id, found_id, score, text, photo, cross, reasons))

    async with conn.transaction():
        rev = await conn.fetchval(f"SELECT match_rev FROM {kind.table} WHERE id = $1 FOR UPDATE", report_id)
        if rev != me["match_rev"]:
            return []   # edited while we worked; the run for the new revision takes over
        await conn.execute(
            f"DELETE FROM lf_matches WHERE {kind.photo_fk} = $1 AND NOT ({other.photo_fk} = ANY($2::uuid[]))",
            report_id, [k[1] if kind is LOST else k[0] for k in kept])
        await conn.executemany(
            """INSERT INTO lf_matches (lost_report_id, found_report_id, score, text_sim, photo_sim, cross_sim, reasons)
               VALUES ($1, $2, $3, $4, $5, $6, $7)
               ON CONFLICT (lost_report_id, found_report_id) DO UPDATE
               SET score = EXCLUDED.score, text_sim = EXCLUDED.text_sim, photo_sim = EXCLUDED.photo_sim,
                   cross_sim = EXCLUDED.cross_sim, reasons = EXCLUDED.reasons, computed_at = now()""", kept)
        pushes = await _alert_strong(conn, kind, report_id, settings.match_strong)
        await conn.execute(f"UPDATE {kind.table} SET matched_rev = $2 WHERE id = $1", report_id, rev)
    return pushes


async def _alert_strong(conn: asyncpg.Connection, kind: Kind, report_id: UUID, strong: float) -> list[Push]:
    """Tell each lost report's owner about a strong new match, once per found report."""
    rows = await conn.fetch(
        f"""UPDATE lf_matches m SET notified_at = now()
            FROM lost_reports l, found_reports f, lf_categories c
            WHERE m.{kind.photo_fk} = $1 AND m.score >= $2 AND m.notified_at IS NULL
              AND l.id = m.lost_report_id AND f.id = m.found_report_id AND c.id = l.category_id
              AND l.status = 'open' AND l.deleted_at IS NULL AND f.status = 'open' AND f.deleted_at IS NULL
            RETURNING m.lost_report_id, m.found_report_id, l.reporter_id, c.name AS category""",
        report_id, strong)
    groups: dict[tuple[UUID, UUID], list[asyncpg.Record]] = {}
    for r in rows:
        groups.setdefault((r["reporter_id"], r["found_report_id"]), []).append(r)
    pushes = []
    for (user_id, found_id), items in groups.items():
        already = await conn.fetchval(
            """SELECT EXISTS (SELECT 1 FROM notifications WHERE user_id = $1 AND type = 'lost_found_match'
                              AND payload->>'found_report_id' = $2)""", user_id, str(found_id))
        if already:
            continue
        message = f"Someone found an item that looks like your lost {items[0]['category']}. Check if it's yours."
        payload = {"found_report_id": str(found_id),
                   "lost_report_ids": [str(i["lost_report_id"]) for i in items], "message": message}
        await create_notifications(conn, [user_id], "lost_found_match", payload)
        pushes.append(([user_id], payload))
    return pushes


async def run_one(kind_name: str, report_id: UUID, embedder: Embedder) -> None:
    """Match one report on its own connection, then send the pushes."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        pushes = await match_report(conn, KINDS[kind_name], report_id, embedder)
    for user_ids, payload in pushes:
        await deliver_push(user_ids, "lost_found_match", payload)


async def backfill(embedder: Embedder) -> int:
    """Match every open report whose latest revision hasn't been matched (e.g. after migration 012,
    or when a matcher invocation failed). Returns how many were matched."""
    pool = await get_pool()
    done = 0
    for kind in (FOUND, LOST):
        async with pool.acquire() as conn:
            ids = [r["id"] for r in await conn.fetch(
                f"""SELECT id FROM {kind.table} WHERE status = 'open' AND deleted_at IS NULL
                      AND matched_rev IS DISTINCT FROM match_rev ORDER BY created_at""")]
        for report_id in ids:
            await run_one(kind.name, report_id, embedder)
            done += 1
    log.info("Backfill matched %d reports", done)
    return done
