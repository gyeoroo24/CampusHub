"""Accuracy suite for automatic flagging of Buy & Sell listings, on the generated test set.

Uses the real bge-small model and the production checks in app/screening.py. Skipped when the model is
missing (run scripts/fetch_match_models.py --suggest-only). The floors are regression gates, set a little
below the numbers in docs/auto-flag-accuracy.md. Known gaps are xfail tests, so they show up in the
report without failing the suite. If a change lowers a metric below its floor, read the report first.
"""
import asyncio

import pytest

import app.categories_suggest as cs
from .auto_flag_eval import binary, evaluate_spam, load_listings, load_spam, run_listings

pytestmark = pytest.mark.skipif(not cs.suggestion_available(), reason="bge-small model not downloaded")


@pytest.fixture(scope="module")
def listings():
    return load_listings()


@pytest.fixture(scope="module")
def decisions(listings):
    return run_listings(listings)


@pytest.fixture(scope="module")
def prohibited_metrics(listings, decisions):
    return binary([bool(r["prohibited"]) for r in listings], decisions[0])


@pytest.fixture(scope="module")
def gibberish_metrics(listings, decisions):
    return binary([bool(r["gibberish"]) for r in listings], decisions[1])


@pytest.fixture(scope="module")
def spam_metrics():
    m, _, _ = asyncio.run(evaluate_spam(load_spam()))
    return m


def test_dataset_covers_each_check(listings):
    assert len(listings) >= 500
    tiers = {r["tier"] for r in listings}
    assert {"prohibited", "lookalike", "clean", "gibberish", "real"} <= tiers
    assert sum(r["prohibited"] for r in listings) >= 120
    assert sum(r["gibberish"] for r in listings) >= 60


def test_prohibited_check_catches_most_and_flags_few_fine_posts(prohibited_metrics):
    assert prohibited_metrics["precision"] >= 0.90
    assert prohibited_metrics["recall"] >= 0.70
    assert prohibited_metrics["false_positive_rate"] <= 0.03


def test_prohibited_look_alikes_are_not_flagged(listings, decisions):
    lookalikes = [p for r, p in zip(listings, decisions[0]) if r["tier"] == "lookalike"]
    assert sum(lookalikes) / len(lookalikes) <= 0.05


def test_ordinary_listings_are_not_held(listings, decisions):
    clean = [p for r, p in zip(listings, decisions[0]) if r["tier"] == "clean"]
    assert sum(clean) / len(clean) <= 0.03


def test_slang_drug_names_are_caught_held_out(listings, decisions):
    """Held-out slang: terms that were not used when the slang rules were written."""
    held_out = [p for r, p in zip(listings, decisions[0]) if r["source"] == "generated:drugs_slang_heldout"]
    assert len(held_out) >= 50
    assert sum(held_out) / len(held_out) >= 0.65


def test_slang_drug_names_are_caught_in_sample(listings, decisions):
    """Caveat: some of these phrases appear in the slang rules, so this number is optimistic."""
    slang = [p for r, p in zip(listings, decisions[0]) if r["source"] == "generated:drugs_slang"]
    assert sum(slang) / len(slang) >= 0.60


def test_gibberish_check_precise(gibberish_metrics):
    assert gibberish_metrics["precision"] >= 0.95
    assert gibberish_metrics["false_positive_rate"] <= 0.01
    assert gibberish_metrics["recall"] >= 0.65


@pytest.mark.parametrize("title", ["JBL Tune 510BT", "RTX3080Ti graphics card", "Lenovo T480", "fx-991ES calculator",
                                   "TV stand", "DVD player", "Hero Sprint 26T", "Btwin Rockrider ST20"])
def test_brands_and_model_codes_are_not_gibberish(title):
    from app.screening import is_gibberish
    assert not is_gibberish(title), title


def test_gibberish_recall_on_random_strings(listings, decisions):
    """Random strings, including ones with digits. Residual misses are strings with only one or two
    letter-digit switches (2ubq0, zq1 xv7), which look like model codes."""
    random_junk = [g for r, g in zip(listings, decisions[1]) if r["source"] == "generated" and r["gibberish"]]
    assert sum(random_junk) / len(random_junk) >= 0.65


def test_real_titles_pass_the_gibberish_check(listings, decisions):
    flagged = [g for r, g in zip(listings, decisions[1]) if r["tier"] == "real"]
    assert 1 - sum(flagged) / len(flagged) >= 0.90


def test_spam_check_accuracy(spam_metrics):
    assert spam_metrics["accuracy"] >= 0.95
    assert spam_metrics["false_positive_rate"] <= 0.02
