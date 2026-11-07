"""Automatic flagging of new posts (app/screening.py)."""
import pytest

import app.matching.trigger as trigger
from app.config import get_settings
from app.screening import is_gibberish, prohibited_reason
from app.categories_suggest import suggestion_available
from .conftest import ADMIN, API, ASHA, MEERA, RAVI, category, grant, image_bytes, make_admin, sign_in, upload


@pytest.fixture
def auto_flag(monkeypatch):
    monkeypatch.setattr(get_settings(), "auto_flag", True)


def _post(client, who, title, cat=None, **extra):
    cat = cat or category(client, who, "buy-sell", "Misc")
    r = client.post(f"{API}/listings", headers=who, json={"title": title, "price": "500", "category_id": cat} | extra)
    assert r.status_code == 201, r.text
    return r.json()


def _moderator(client):
    make_admin(client, ADMIN)
    sign_in(client, MEERA)
    assert grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell").status_code == 201


def _queue(client, who=MEERA):
    return client.get(f"{API}/reports", headers=who).json()["items"]


def _notices(client, who):
    return [n["payload"]["message"] for n in client.get(f"{API}/me/notifications", headers=who).json()["items"]
            if n["type"] == "moderation_action"]


def test_prohibited_item_is_held_and_queued(client, auto_flag):
    _moderator(client)
    listing = _post(client, ASHA, "good quality ganja, 10g")
    assert listing["held_for_review"] is True                       # the seller sees it, marked held
    assert client.get(f"{API}/listings/{listing['id']}", headers=RAVI).status_code == 404
    assert [i["id"] for i in client.get(f"{API}/listings").json()["items"]] == []
    [report] = _queue(client)
    assert report["source"] == "system" and report["reporter"] is None
    assert report["target_title"] == "good quality ganja, 10g" and '"ganja"' in report["reason"]
    assert "hidden until a moderator reviews it" in _notices(client, ASHA)[0]

    # Not illegal after all: dismissing the flag puts it back.
    assert client.post(f"{API}/reports/{report['id']}/resolve", headers=MEERA,
                       json={"action": "dismissed"}).status_code == 200
    assert client.get(f"{API}/listings/{listing['id']}", headers=RAVI).json()["held_for_review"] is False


def test_confirmed_removal_of_a_flagged_listing_is_a_strike(client, auto_flag):
    _moderator(client)
    listing = _post(client, ASHA, "Old Monk rum bottle sealed")
    [report] = _queue(client)
    r = client.post(f"{API}/reports/{report['id']}/resolve", headers=MEERA,
                    json={"action": "actioned", "remove_content": True, "severity": "severe", "note": "Alcohol"})
    assert r.json()["content_removed"] is True
    [strike] = client.get(f"{API}/me/seller-strikes", headers=ASHA).json()
    assert strike["severity"] == "severe" and strike["listing_title"] == listing["title"]


def test_gibberish_and_spam_are_flagged_but_stay_visible(client, auto_flag):
    _moderator(client)
    junk = _post(client, ASHA, "asdfghjk")
    assert junk["held_for_review"] is False
    assert client.get(f"{API}/listings/{junk['id']}", headers=RAVI).status_code == 200
    cat = category(client, RAVI, "buy-sell", "Cycles")
    for _ in range(3):
        last = _post(client, RAVI, "Hero Sprint cycle for sale", cat)
    reasons = {r["target_title"]: r["reason"] for r in _queue(client)}
    assert "gibberish title" in reasons["asdfghjk"]
    assert "possible spam (posted 3 near-identical times in 24 hours)" in reasons["Hero Sprint cycle for sale"]
    assert len(reasons) == 2 and last["held_for_review"] is False
    assert "flagged automatically" in _notices(client, ASHA)[0]


def test_ordinary_posts_are_not_flagged(client, auto_flag):
    _moderator(client)
    for title in ("Btwin Rockrider ST20", "HC Verma physics vol 1", "Milton water bottle", "Prestige kitchen knife set"):
        _post(client, ASHA, title)
    assert _queue(client) == []


def test_lost_and_found_gibberish_is_flagged(client, auto_flag):
    _moderator(client)
    grant(client, ADMIN, "meera@iisc.ac.in", "lost_found")
    cat = category(client, ASHA, "lost-found", "Misc")
    r = client.post(f"{API}/lost-reports", headers=ASHA, json={
        "description": "qwertyuiop", "category_id": cat, "occurred_at": "2026-11-01T10:00:00+05:30"})
    assert r.status_code == 201
    [report] = _queue(client)
    assert report["target_type"] == "lost_report" and "gibberish description" in report["reason"]


def test_obscene_photo_is_flagged_after_the_response(client, s3, auto_flag, monkeypatch):
    class FakeNsfw:
        def probability(self, data):
            return 0.97 if image_bytes(data) == b"obscene" else 0.01

    monkeypatch.setattr(trigger, "match_mode", lambda: "inline")
    monkeypatch.setattr(trigger, "get_nsfw_classifier", lambda: FakeNsfw())
    _moderator(client)
    fine = [upload(client, s3, ASHA, "listing_photo", b"fine") for _ in range(2)]
    bad = upload(client, s3, ASHA, "listing_photo", b"obscene")
    _post(client, ASHA, "Study table", photo_keys=[fine[0]])
    assert _queue(client) == []
    _post(client, ASHA, "Study chair", photo_keys=[fine[1], bad])
    [report] = _queue(client)
    assert report["target_title"] == "Study chair" and "possible obscene photo (1 of 2)" in report["reason"]


def test_turned_off_means_no_flags(client):
    _moderator(client)
    _post(client, ASHA, "ganja")
    assert _queue(client) == []


def test_gibberish_heuristic():
    for junk in ("asdfgh", "hbhbbkh", "musssiiccc", "jjjjjj", "zxcvbn", "xkcdzzzz"):
        assert is_gibberish(junk), junk
    for real in ("Btwin Rockrider ST20", "Haier fridge", "Yonex Muscle Power", "1st floor", "Macbook", "iPhone 12"):
        assert not is_gibberish(real), real


@pytest.mark.skipif(not suggestion_available(), reason="bge-small model not downloaded")
def test_prohibited_similarity_without_keywords():
    for bad in ("GATE question paper leak", "fake id card", "rolex replica first copy",
                "will write your assignments for money"):
        assert prohibited_reason(bad), bad
    for fine in ("BB gun toy", "kitchen knife set", "beer mug", "GATE CS previous papers bundle",
                 "glass water bottle", "fake plant decor", "swiss army knife style multitool"):
        assert prohibited_reason(fine) is None, fine
