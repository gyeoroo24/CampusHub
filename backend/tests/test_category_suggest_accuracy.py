"""Accuracy suite for category suggestion: the real bge-small model on the generated test set.

Skipped when the model files or onnxruntime are missing (run scripts/fetch_match_models.py --suggest-only).
The floors are regression gates, set a little below the numbers from scripts/eval_category_suggest.py
(see docs/category-suggest-accuracy.md). If a change lowers a metric below its floor, look at the report
before lowering the floor.
"""
from collections import Counter

import pytest

import app.categories_suggest as cs
from .category_suggest_eval import (BASE_CATS, EXAMPLES, EXTRA_CATS, calibration_rows, evaluate, load_rows, rankings)

pytestmark = pytest.mark.skipif(not cs.suggestion_available(), reason="bge-small model not downloaded")


@pytest.fixture(scope="module")
def rows():
    return load_rows()


@pytest.fixture(scope="module")
def embedder():
    return cs.BgeEmbedder(cs.model_dir())


@pytest.fixture(scope="module")
def base(rows, embedder):
    return evaluate(rows, rankings(embedder, rows, BASE_CATS, EXAMPLES), BASE_CATS)


@pytest.fixture(scope="module")
def extended(rows, embedder):
    cats = BASE_CATS + EXTRA_CATS
    return evaluate(rows, rankings(embedder, rows, cats, EXAMPLES), cats)


def test_dataset_is_big_enough_and_covers_every_category(rows):
    assert len(rows) >= 500
    gold = Counter(c for r in rows for c in r["gold"])
    for cat in BASE_CATS + EXTRA_CATS:
        assert gold[cat] >= 20, f"too few test rows for {cat}: {gold[cat]}"
    assert sum(1 for r in rows if not r["gold"]) >= 40   # negatives: nothing fits


def test_base_ranking_and_suggestions(base):
    assert base["top1_accuracy"] >= 0.80       # the right category is the top pick
    assert base["precision"] >= 0.80           # a suggestion is usually right
    assert base["f1"] >= 0.70


def test_base_stays_quiet_when_nothing_fits(base):
    assert base["abstain_on_negatives"] >= 0.80
    assert base["by_tier"]["none"]["accuracy"] >= 0.85


def test_extended_suggestions_stay_precise(extended):
    assert extended["precision"] >= 0.85       # new categories must not bring wrong suggestions
    assert extended["abstain_on_negatives"] >= 0.85
    assert extended["macro_f1"] >= 0.60


def test_calibration_titles_still_pass(embedder):
    cal = calibration_rows()
    m = evaluate(cal, rankings(embedder, cal, BASE_CATS, EXAMPLES), BASE_CATS)
    assert m["top1_accuracy"] >= 0.85
    assert m["precision"] >= 0.90
