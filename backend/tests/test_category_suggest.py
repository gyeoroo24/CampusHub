"""Category suggestion from a title (app/categories_suggest.py)."""
import numpy as np
import pytest

import app.categories_suggest as cs
from .conftest import API, ASHA, category

WORDS = ["plant", "pot", "bottle", "flask", "table", "chair", "book"]


class FakeBge:
    """Words map to fixed directions; anything else gets its own direction."""
    def embed(self, texts):
        out = []
        for t in texts:
            t = t.removeprefix(cs.QUERY_PREFIX).lower()
            v = np.array([1.0 if w in t else 0.0 for w in WORDS] + [0.3], dtype=np.float32)
            out.append(v / np.linalg.norm(v))
        return np.array(out)


@pytest.fixture
def fake_model(monkeypatch):
    monkeypatch.setattr(cs, "suggestion_available", lambda: True)
    monkeypatch.setattr(cs, "get_embedder", lambda: FakeBge())


def _suggest(client, path, title):
    r = client.get(f"{API}/{path}/categories/suggest", params={"title": title})
    assert r.status_code == 200, r.text
    return r.json()["category"]


def test_pick_needs_both_the_threshold_and_a_clear_lead():
    ranked = [(1, "Plant", 0.70), (2, "Bottle", 0.69), (3, "Books", 0.2)]
    assert cs.pick(ranked, 0.5, 0.03) is None            # too close to call
    assert cs.pick(ranked, 0.5, 0.0) == (1, "Plant")
    assert cs.pick([(1, "Plant", 0.4)], 0.5, 0.0) is None  # not similar enough
    assert cs.pick([], 0.5, 0.0) is None


def test_categories_are_compared_as_phrases_not_bare_names():
    assert cs.category_phrase("  Kitchen & Appliances ") == "a kitchen & appliances item for sale"


def test_recent_listings_pull_a_title_towards_their_category():
    categories = [(1, "Garden"), (2, "Bottle")]
    without = dict((name, score) for _, name, score in cs.rank(FakeBge(), "money plant in a pot", categories, {}))
    with_examples = cs.rank(FakeBge(), "money plant in a pot", categories, {1: ["Snake plant in a pot"]})
    assert with_examples[0][:2] == (1, "Garden")
    assert with_examples[0][2] > without["Garden"]


def test_suggests_the_fitting_existing_category(client, fake_model):
    plant = category(client, ASHA, "buy-sell", "Plant")
    category(client, ASHA, "buy-sell", "Bottle")
    category(client, ASHA, "buy-sell", "Books")
    assert _suggest(client, "buy-sell", "plant") == {"id": plant, "name": "Plant"}
    assert _suggest(client, "buy-sell", "Something else entirely") is None


def test_stays_quiet_when_no_category_fits(client, fake_model):
    """The original bug: with no Plant category, "plant" was suggested "Bottle"."""
    category(client, ASHA, "buy-sell", "Bottle")
    category(client, ASHA, "buy-sell", "Books")
    assert _suggest(client, "buy-sell", "plant") is None


def test_lost_and_found_uses_its_own_categories(client, fake_model):
    flask = category(client, ASHA, "lost-found", "Flask")
    category(client, ASHA, "buy-sell", "Plant")
    assert _suggest(client, "lost-found", "steel flask") == {"id": flask, "name": "Flask"}
    assert _suggest(client, "lost-found", "plant") is None


def test_no_model_means_no_suggestion(client, monkeypatch):
    monkeypatch.setattr(cs, "suggestion_available", lambda: False)
    category(client, ASHA, "buy-sell", "Plant")
    assert _suggest(client, "buy-sell", "plant") is None


@pytest.mark.skipif(not cs.suggestion_available(), reason="bge-small model not downloaded")
def test_real_model_on_a_few_titles():
    emb = cs.BgeEmbedder(cs.model_dir())
    names = ["Books", "Electronics", "Cycles", "Furniture", "Clothing", "Kitchen & Appliances",
             "Sports & Fitness", "Stationery", "Bottle"]
    cats = list(enumerate(names))

    examples = {3: ["Ergonomic office chair", "Study table with drawer", "Single-bed mattress (Sleepwell)"],
                0: ["Introduction to Algorithms (CLRS), 3rd ed", "Deep Learning - Goodfellow et al."]}

    def suggest(title, categories=cats, examples=examples):
        return cs.pick(cs.rank(emb, title, categories, examples), 0.52, 0.03)

    assert suggest("used study table")[1] == "Furniture"
    # With no listings yet, Books and Furniture are too close to call: it stays quiet instead of guessing.
    assert suggest("used study table", examples={}) in (None, (3, "Furniture"))
    assert suggest("Milton water bottle 1L")[1] == "Bottle"
    assert suggest("Hero Sprint geared bicycle")[1] == "Cycles"
    assert suggest("asdfgh") is None
    assert suggest("money plant in a pot") is None   # no Plant category: no guess
    assert suggest("money plant in a pot", cats + [(9, "Plant")])[1] == "Plant"


def test_moderators_delete_categories_moving_what_used_them(client):
    from .conftest import ADMIN, KIRAN, MEERA, grant, make_admin, sign_in
    make_admin(client, ADMIN)
    sign_in(client, MEERA)
    sign_in(client, KIRAN)
    junk = category(client, ASHA, "buy-sell", "musssiiccc")
    music = category(client, ASHA, "buy-sell", "Musical Instruments")
    unused = category(client, ASHA, "buy-sell", "hello")
    listing = client.post(f"{API}/listings", headers=ASHA, json={
        "title": "Yamaha guitar", "price": "4000", "category_id": junk}).json()
    url = f"{API}/buy-sell/categories"
    assert client.delete(f"{url}/{unused}", headers=ASHA).status_code == 403          # not a moderator
    assert client.delete(f"{url}/{unused}", headers=ADMIN).status_code == 204         # nothing uses it
    r = client.delete(f"{url}/{junk}", headers=ADMIN)
    assert r.status_code == 409 and "1 listings" in r.json()["detail"]
    assert client.delete(f"{url}/{junk}?move_to={junk}", headers=ADMIN).status_code == 422
    assert grant(client, ADMIN, "meera@iisc.ac.in", "buy_sell").status_code == 201
    assert client.delete(f"{url}/{junk}?move_to={music}", headers=MEERA).status_code == 204
    assert client.get(f"{API}/listings/{listing['id']}").json()["category"]["name"] == "Musical Instruments"
    assert [c["name"] for c in client.get(url).json()] == ["Musical Instruments"]
    # A Lost & Found moderator can't touch Buy & Sell categories.
    assert grant(client, ADMIN, "kiran@iisc.ac.in", "lost_found").status_code == 201
    assert client.delete(f"{url}/{music}", headers=KIRAN).status_code == 403
