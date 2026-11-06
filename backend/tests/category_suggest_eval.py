"""Metrics for category suggestion (app/categories_suggest.py) on labelled titles.

Used by scripts/eval_category_suggest.py (writes the report) and tests/test_category_suggest_accuracy.py
(regression floors). A row is a positive when at least one of its gold categories is in the category
list being tested; otherwise it is a negative and the suggester must stay quiet. A suggestion is correct
only when it names one of the gold categories.
"""
import csv
import pathlib
import sys
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "tests" / "data" / "category_suggest_eval.csv"
sys.path.insert(0, str(ROOT / "scripts"))

from app.categories_suggest import pick, rank  # noqa: E402
from calibrate_category_suggest import EXAMPLES  # noqa: E402,F401  (re-exported: recent listings per category)

# The eleven categories of the calibration set (the list the thresholds were chosen on).
BASE_CATS = ["Books", "Electronics", "Cycles", "Furniture", "Clothing", "Kitchen & Appliances",
             "Sports & Fitness", "Stationery", "Plant", "Bottle", "Musical Instruments"]
# Temporary categories for the extended setting. They exist only in memory during evaluation.
EXTRA_CATS = ["Pet Supplies", "Garden Tools", "Board Games", "Art Supplies", "Toys"]
THRESHOLD = 0.52   # config.category_suggest_threshold
MARGIN = 0.03      # config.category_suggest_margin


def load_rows(path=CSV_PATH):
    with open(path, newline="") as f:
        return [{"title": r["title"], "gold": set(filter(None, r["gold"].split("|"))), "tier": r["tier"],
                 "source": r["source"]} for r in csv.DictReader(f)]


def calibration_rows():
    """The 87 hand-written calibration titles, in the same row format."""
    from calibrate_category_suggest import TITLES
    return [{"title": t, "gold": set(g), "tier": "calibration", "source": "hand-written"} for t, g in TITLES]


def rankings(embedder, rows, cats, examples):
    """Ranked (id, name, score) lists for every row, computed once and reused for every threshold."""
    categories = list(enumerate(cats))
    ex = {i: examples[c] for i, c in categories if c in examples}
    return [rank(embedder, r["title"], categories, ex) for r in rows]


def evaluate(rows, ranked_lists, cats, threshold=THRESHOLD, margin=MARGIN):
    decisions = []
    for ranked in ranked_lists:
        decisions.append(pick(ranked, threshold, margin))

    cat_set = set(cats)
    pos = neg = top1 = suggested = correct = abstained_neg = 0
    tiers = defaultdict(lambda: [0, 0])       # tier -> [rows, correct decisions]
    per_cat = defaultdict(lambda: Counter())  # category -> counts of tp, fp, fn
    confusions = Counter()
    failures = []
    for row, ranked, choice in zip(rows, ranked_lists, decisions):
        gold = row["gold"] & cat_set
        ok = False
        if gold:
            pos += 1
            top1 += ranked[0][1] in gold
            if choice is None:
                ok = False
            elif choice[1] in gold:
                correct += 1
                ok = True
            else:
                confusions[(tuple(sorted(gold)), choice[1])] += 1
        else:
            neg += 1
            ok = choice is None
            abstained_neg += ok
        if choice is not None:
            suggested += 1
        if choice is not None and not ok:
            failures.append((row["title"], sorted(row["gold"]), choice[1], round(ranked[0][2], 3)))
        for c in cat_set:
            hit_gold = c in gold
            hit_pred = choice is not None and choice[1] == c
            if hit_gold and hit_pred:
                per_cat[c]["tp"] += 1
            elif hit_pred:
                per_cat[c]["fp"] += 1
            elif hit_gold:
                per_cat[c]["fn"] += 1
        tiers[row["tier"]][0] += 1
        tiers[row["tier"]][1] += ok

    precision = correct / suggested if suggested else 0.0
    recall = correct / pos if pos else 0.0
    f1_scores = {}
    for c in cat_set:
        tp, fp, fn = per_cat[c]["tp"], per_cat[c]["fp"], per_cat[c]["fn"]
        if tp + fn:   # only categories that have positive rows in this set
            p = tp / (tp + fp) if tp + fp else 0.0
            r = tp / (tp + fn)
            f1_scores[c] = 2 * p * r / (p + r) if p + r else 0.0
    return {
        "rows": len(rows), "positives": pos, "negatives": neg,
        "top1_accuracy": top1 / pos if pos else 0.0,
        "suggested": suggested, "correct_suggestions": correct,
        "precision": precision, "recall": recall,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0.0,
        "macro_f1": sum(f1_scores.values()) / len(f1_scores) if f1_scores else 0.0,
        "abstain_on_negatives": abstained_neg / neg if neg else 0.0,
        "decision_accuracy": (correct + abstained_neg) / len(rows) if rows else 0.0,
        "by_tier": {t: {"rows": n, "accuracy": k / n} for t, (n, k) in sorted(tiers.items())},
        "per_category_f1": dict(sorted(f1_scores.items())),
        "top_confusions": confusions.most_common(10),
        "wrong_suggestions": failures,
    }


def sweep(rows, ranked_lists, cats, thresholds=(0.40, 0.44, 0.48, 0.52, 0.56, 0.60, 0.64)):
    out = []
    for t in thresholds:
        m = evaluate(rows, ranked_lists, cats, threshold=t, margin=MARGIN)
        out.append((t, m["suggested"], m["correct_suggestions"], m["precision"], m["recall"], m["abstain_on_negatives"]))
    return out
