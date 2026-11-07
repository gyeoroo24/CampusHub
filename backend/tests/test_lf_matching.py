"""Lost & Found matching by description and photo (app/matching, future plan §1.2).

The real models aren't needed: FakeEmbedder maps words to fixed directions, so similarities
are exact and the expected scores follow from app/matching/engine.py's SIGNALS.
"""
import hashlib
from datetime import datetime, timedelta, timezone

import numpy as np
import pytest

import app.matching.trigger as trigger
import app.routers.lost_found as lost_found
from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, category, image_bytes, make_admin, sql, upload

WORDS = ["earbuds", "wallet", "bottle", "black", "brown"]
EXTRA = 40   # descriptions with none of WORDS get their own direction, so they don't match each other


def _vec(text: str) -> list[float]:
    v = np.zeros(len(WORDS) + EXTRA, dtype=np.float32)
    for i, w in enumerate(WORDS):
        if w in text.lower():
            v[i] = 1
    if not v.any():
        v[len(WORDS) + int(hashlib.sha256(text.encode()).hexdigest(), 16) % EXTRA] = 1
    return (v / np.linalg.norm(v)).tolist()


class FakeEmbedder:
    def __init__(self):
        self.calls = []
        self.during_text = None   # hook: runs while a description is being embedded

    def text(self, description):
        self.calls.append(("text", description))
        if self.during_text:
            self.during_text()
        return _vec(description)

    def clip_text(self, description):
        return _vec(description)

    def image(self, data):
        data = image_bytes(data)
        self.calls.append(("image", data))
        if data == b"not an image":
            return None
        return _vec(data.decode().removeprefix("photo:"))


@pytest.fixture
def matcher(monkeypatch):
    fake = FakeEmbedder()
    monkeypatch.setattr(trigger, "match_mode", lambda: "inline")
    monkeypatch.setattr(lost_found, "match_mode", lambda: "inline")
    monkeypatch.setattr(trigger, "get_embedder", lambda: fake)
    return fake


def _when(days_ago: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).isoformat()


def _file(client, headers, kind, cat, days_ago, description, **extra):
    r = client.post(f"{API}/{kind}-reports", headers=headers, json={
        "description": description, "category_id": cat, "occurred_at": _when(days_ago)} | extra)
    assert r.status_code == 201, r.text
    return r.json()


def _matches(client, headers, kind, report_id):
    r = client.get(f"{API}/{kind}-reports/{report_id}/matches", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _alerts(client, headers):
    return [n for n in client.get(f"{API}/me/notifications", headers=headers).json()["items"]
            if n["type"] == "lost_found_match"]


def test_strong_match_across_categories_alerts_the_owner(client, matcher):
    electronics = category(client, ASHA, "lost-found", "Electronics")
    accessories = category(client, ASHA, "lost-found", "Accessories")
    wallets = category(client, ASHA, "lost-found", "Wallet")
    lost = _file(client, ASHA, "lost", electronics, 2, "Earbuds in a case near the library")
    _file(client, KIRAN, "lost", wallets, 2, "Wallet with a bank card")
    found = _file(client, MEERA, "found", accessories, 1, "Found earbuds on a table")

    result = _matches(client, ASHA, "lost", lost["id"])
    assert result["status"] == "ready"
    [m] = result["matches"]
    assert m["report"]["id"] == found["id"] and m["strength"] == "strong" and m["score"] == 1.0
    assert "Similar description" in m["reasons"] and "Same category" not in m["reasons"]

    [alert] = _alerts(client, ASHA)
    assert alert["payload"]["found_report_id"] == found["id"]
    assert alert["payload"]["lost_report_ids"] == [lost["id"]]
    assert _alerts(client, KIRAN) == [] and _alerts(client, MEERA) == []
    # The finder sees the same pair from their side, without being alerted.
    assert [m["report"]["id"] for m in _matches(client, MEERA, "found", found["id"])["matches"]] == [lost["id"]]


def test_a_new_lost_report_matching_an_older_found_one_alerts_its_owner(client, matcher):
    cat = category(client, ASHA, "lost-found", "Electronics")
    found = _file(client, MEERA, "found", cat, 1, "Earbuds found in the gym")
    lost = _file(client, ASHA, "lost", cat, 2, "Lost my earbuds")
    [alert] = _alerts(client, ASHA)
    assert alert["payload"] == {"found_report_id": found["id"], "lost_report_ids": [lost["id"]],
                                "message": alert["payload"]["message"]}
    assert "Electronics" in alert["payload"]["message"]


def test_look_alike_is_listed_but_not_alerted_and_order_is_by_score(client, matcher):
    cat = category(client, ASHA, "lost-found", "Wallet")
    lost = _file(client, ASHA, "lost", cat, 3, "Brown wallet")
    close = _file(client, MEERA, "found", cat, 1, "A brown wallet")
    similar = _file(client, RAVI, "found", cat, 1, "Black wallet")   # half the words in common
    _file(client, KIRAN, "found", cat, 1, "Water bottle")            # nothing in common

    matches = _matches(client, ASHA, "lost", lost["id"])["matches"]
    assert [m["report"]["id"] for m in matches] == [close["id"], similar["id"]]
    assert [m["strength"] for m in matches] == ["strong", "possible"]
    assert [a["payload"]["found_report_id"] for a in _alerts(client, ASHA)] == [close["id"]]


def test_photos_match_photos_and_descriptions(client, s3, matcher):
    cat = category(client, ASHA, "lost-found", "Misc")
    mine = upload(client, s3, ASHA, "lost_report_photo", b"photo:earbuds")
    theirs = upload(client, s3, MEERA, "found_report_photo", b"photo:earbuds")
    lost = _file(client, ASHA, "lost", cat, 2, "Left it after class", photo_keys=[mine])
    found = _file(client, MEERA, "found", cat, 1, "Picked this up in hall 3", photo_keys=[theirs])
    [m] = _matches(client, ASHA, "lost", lost["id"])["matches"]
    assert m["report"]["id"] == found["id"] and m["strength"] == "strong"
    assert "Similar photo" in m["reasons"]

    # A description alone can match a photo, but that signal is capped: listed, not alerted.
    text_only = _file(client, RAVI, "lost", cat, 2, "Earbuds, white")
    [m] = _matches(client, RAVI, "lost", text_only["id"])["matches"]
    assert m["report"]["id"] == found["id"] and m["strength"] == "possible"
    assert m["reasons"] == ["Photo fits the description", "Same category"]
    assert _alerts(client, RAVI) == []


def test_editing_rematches_without_alerting_twice(client, s3, matcher):
    cat = category(client, ASHA, "lost-found", "Misc")
    lost = _file(client, ASHA, "lost", cat, 2, "Earbuds")
    found = _file(client, MEERA, "found", cat, 1, "Some keys")
    assert _matches(client, ASHA, "lost", lost["id"])["matches"] == []

    r = client.patch(f"{API}/found-reports/{found['id']}", headers=MEERA, json={"description": "Earbuds, black"})
    assert r.status_code == 200
    assert [m["report"]["id"] for m in _matches(client, ASHA, "lost", lost["id"])["matches"]] == [found["id"]]
    client.patch(f"{API}/found-reports/{found['id']}", headers=MEERA, json={"description": "Earbuds in a case"})
    assert len(_alerts(client, ASHA)) == 1

    # Unchanged descriptions aren't embedded again.
    before = len([c for c in matcher.calls if c[0] == "text"])
    client.put(f"{API}/lost-reports/{lost['id']}/photos", headers=ASHA, json={"photo_keys": []})
    assert len([c for c in matcher.calls if c[0] == "text"]) == before


def test_closed_and_removed_reports_drop_out_and_reopening_rematches(client, matcher):
    cat = category(client, ASHA, "lost-found", "Misc")
    lost = _file(client, ASHA, "lost", cat, 2, "Earbuds")
    found = _file(client, MEERA, "found", cat, 1, "Earbuds")
    status = f"{API}/found-reports/{found['id']}/status"
    client.patch(status, headers=MEERA, json={"status": "closed"})
    assert _matches(client, ASHA, "lost", lost["id"])["matches"] == []
    sql("DELETE FROM lf_matches")
    client.patch(status, headers=MEERA, json={"status": "open"})
    assert len(_matches(client, ASHA, "lost", lost["id"])["matches"]) == 1
    assert client.delete(f"{API}/found-reports/{found['id']}", headers=MEERA).status_code == 204
    assert _matches(client, ASHA, "lost", lost["id"])["matches"] == []


def test_time_rule_excludes_items_found_before_they_were_lost(client, matcher):
    cat = category(client, ASHA, "lost-found", "Misc")
    _file(client, MEERA, "found", cat, 10, "Earbuds")
    lost = _file(client, ASHA, "lost", cat, 2, "Earbuds")
    assert _matches(client, ASHA, "lost", lost["id"])["matches"] == []


def test_photos_are_embedded_once_and_dropped_when_removed(client, s3, matcher):
    cat = category(client, ASHA, "lost-found", "Misc")
    good = upload(client, s3, ASHA, "lost_report_photo", b"photo:wallet")
    bad = upload(client, s3, ASHA, "lost_report_photo", b"not an image")
    lost = _file(client, ASHA, "lost", cat, 2, "Lost it", photo_keys=[good, bad])
    rows = sql("SELECT s3_key, cardinality(vec) AS n FROM lf_embeddings WHERE s3_key IS NOT NULL ORDER BY n")
    assert [(r["s3_key"], r["n"]) for r in rows] == [(bad, 0), (good, len(WORDS) + EXTRA)]
    client.patch(f"{API}/lost-reports/{lost['id']}", headers=ASHA, json={"description": "Lost it again"})
    assert len([c for c in matcher.calls if c[0] == "image"]) == 2   # not fetched again
    client.put(f"{API}/lost-reports/{lost['id']}/photos", headers=ASHA, json={"photo_keys": [good]})
    assert [r["s3_key"] for r in sql("SELECT s3_key FROM lf_embeddings WHERE s3_key IS NOT NULL")] == [good]


def test_pending_until_matched_and_an_edit_mid_run_stays_pending(client, matcher):
    cat = category(client, ASHA, "lost-found", "Misc")
    lost = _file(client, ASHA, "lost", cat, 2, "Earbuds")
    assert _matches(client, ASHA, "lost", lost["id"])["status"] == "ready"
    sql("UPDATE lost_reports SET match_rev = match_rev + 1 WHERE id = $1::uuid", lost["id"])
    assert _matches(client, ASHA, "lost", lost["id"])["status"] == "pending"

    # Someone edits the report while the matcher is working: the run doesn't mark it done.
    matcher.during_text = lambda: sql("UPDATE lost_reports SET match_rev = match_rev + 1 WHERE id = $1::uuid",
                                      lost["id"])
    client.patch(f"{API}/lost-reports/{lost['id']}", headers=ASHA, json={"description": "Earbuds, black"})
    assert _matches(client, ASHA, "lost", lost["id"])["status"] == "pending"


def test_only_the_reporter_or_an_admin_sees_matches(client, matcher):
    cat = category(client, ASHA, "lost-found", "Misc")
    lost = _file(client, ASHA, "lost", cat, 2, "Earbuds")
    url = f"{API}/lost-reports/{lost['id']}/matches"
    assert client.get(url, headers=RAVI).status_code == 403
    assert client.get(url).status_code == 401
    make_admin(client, ADMIN)
    assert client.get(url, headers=ADMIN).status_code == 200


def test_without_the_matcher_the_old_rule_applies(client):
    """match_mode off (as in the rest of the suite): same category, unranked, everyone alerted."""
    cat = category(client, ASHA, "lost-found", "ID card")
    lost = _file(client, ASHA, "lost", cat, 2, "Blue ID card")
    found = _file(client, MEERA, "found", cat, 1, "Found a wallet")   # unrelated words, same category
    result = _matches(client, ASHA, "lost", lost["id"])
    assert result["status"] == "unavailable"
    assert [(m["report"]["id"], m["strength"], m["score"]) for m in result["matches"]] == [(found["id"], None, None)]
    assert len(_alerts(client, ASHA)) == 1
    assert sql("SELECT count(*) AS n FROM lf_embeddings")[0]["n"] == 0


def test_lambda_mode_invokes_the_matcher_asynchronously(client, monkeypatch):
    calls = []

    class FakeLambda:
        def invoke(self, **kwargs):
            calls.append(kwargs)

    monkeypatch.setattr(trigger, "match_mode", lambda: "lambda")
    monkeypatch.setattr(lost_found, "match_mode", lambda: "lambda")
    monkeypatch.setattr(trigger, "_lambda_client", lambda: FakeLambda())
    cat = category(client, ASHA, "lost-found", "Misc")
    lost = _file(client, ASHA, "lost", cat, 2, "Earbuds")
    [call] = calls
    assert call["InvocationType"] == "Event"
    assert call["Payload"] == f'{{"kind": "lost", "report_id": "{lost["id"]}"}}'.encode()
    assert _matches(client, ASHA, "lost", lost["id"])["status"] == "pending"
