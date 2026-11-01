"""Metrics for automatic flagging of Buy & Sell listings (app/screening.py) on the generated test set.

The checks are the production functions: prohibited_reason() (word list, then bge similarity),
is_gibberish() and _spam_reason(). Spam needs the seller's recent posts from the database, so the
evaluator passes a stub connection that returns each scenario's history in the shape the SQL returns.

Metrics are per check and for the listing as a whole (flagged if any check fires). "held" means the
prohibited check fired, which hides the listing until a moderator decides.
"""
import csv
import json
import pathlib
import sys
import uuid
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA = ROOT / "tests" / "data"
LISTINGS_CSV = DATA / "auto_flag_eval.csv"
SPAM_JSON = DATA / "spam_eval.json"
sys.path.insert(0, str(ROOT))

import app.screening as sc  # noqa: E402
from app.categories_suggest import QUERY_PREFIX, get_embedder  # noqa: E402

PROHIBITED_AT = sc.PROHIBITED_AT   # config-free constant used by prohibited_reason()


def load_listings(path=LISTINGS_CSV):
    with open(path, newline="") as f:
        return [{"title": r["title"], "prohibited": int(r["gold_prohibited"]), "gibberish": int(r["gold_gibberish"]),
                 "tier": r["tier"], "source": r["source"]} for r in csv.DictReader(f)]


def load_spam(path=SPAM_JSON):
    return json.loads(path.read_text())


def binary(gold, pred):
    """Precision, recall, F1, accuracy and false-positive rate for one check."""
    tp = sum(g and p for g, p in zip(gold, pred))
    fp = sum((not g) and p for g, p in zip(gold, pred))
    fn = sum(g and (not p) for g, p in zip(gold, pred))
    tn = sum((not g) and (not p) for g, p in zip(gold, pred))
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    return {
        "n": len(gold), "positives": sum(gold), "negatives": len(gold) - sum(gold),
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "precision": precision, "recall": recall,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0.0,
        "accuracy": (tp + tn) / len(gold) if gold else 0.0,
        "false_positive_rate": fp / (fp + tn) if fp + tn else 0.0,
    }


def prohibited_scores(texts):
    """Closest prohibited and harmless similarity for each text (the same numbers prohibited_reason() uses)."""
    emb = get_embedder()
    vecs = emb.embed([QUERY_PREFIX + t[:500] for t in texts])
    bad_m = emb.embed(sc.PROHIBITED) @ vecs.T
    good_m = emb.embed(sc.HARMLESS) @ vecs.T
    return [(float(bad_m[:, i].max()), float(good_m[:, i].max()), int(bad_m[:, i].argmax()))
            for i in range(len(texts))]


def similarity_only(scores, threshold=PROHIBITED_AT, lead=sc.PROHIBITED_LEAD):
    return [bad >= threshold and bad - good >= lead for bad, good, _ in scores]


class StubConn:
    """Returns a scenario's history in the shape _spam_reason's SQL returns it."""

    def __init__(self, history):
        self.rows = [{"id": uuid.uuid4(), "text": h["text"], "last_hour": h["minutes_ago"] < 60}
                     for h in history]

    async def fetch(self, sql, *args):
        return self.rows


async def spam_decision(scenario):
    t = sc.TARGETS["listing"]
    reason = await sc._spam_reason(StubConn(scenario["history"]), t, uuid.uuid4(), uuid.uuid4(), scenario["title"])
    return reason


def run_listings(listings):
    """Production decisions for every listing: prohibited (full), gibberish, and the two combined."""
    texts = [r["title"] for r in listings]
    prohibited = []
    for t in texts:
        prohibited.append(sc.prohibited_reason(t) is not None)
    gibberish = [sc.is_gibberish(t) for t in texts]
    return prohibited, gibberish


def group_recall(listings, pred_flags, key):
    """Recall of one check per prohibited group (rows where the gold label is the group)."""
    counts = defaultdict(lambda: [0, 0])
    for r, p in zip(listings, pred_flags):
        if r["prohibited"]:
            group = r["source"].split(":", 1)[1] if ":" in r["source"] else "other"
            counts[group][0] += 1
            counts[group][1] += bool(p)
    return {g: (n, k, k / n) for g, (n, k) in sorted(counts.items())}


def sweep(listings, scores, thresholds=(0.50, 0.54, 0.58, 0.60, 0.62, 0.66, 0.70)):
    gold = [bool(r["prohibited"]) for r in listings]
    out = []
    for t in thresholds:
        m = binary(gold, similarity_only(scores, threshold=t))
        out.append((t, m["precision"], m["recall"], m["false_positive_rate"]))
    return out


async def evaluate_spam(scenarios):
    gold, pred, by_kind = [], [], defaultdict(lambda: [0, 0])
    errors = []
    for s in scenarios:
        reason = await spam_decision(s)
        p = reason is not None
        gold.append(bool(s["gold_spam"]))
        pred.append(p)
        by_kind[s["kind"]][0] += 1
        by_kind[s["kind"]][1] += (p == bool(s["gold_spam"]))
        if p != bool(s["gold_spam"]):
            errors.append((s["kind"], s["title"], bool(s["gold_spam"]), reason))
    return binary(gold, pred), {k: (n, c, c / n) for k, (n, c) in sorted(by_kind.items())}, errors
