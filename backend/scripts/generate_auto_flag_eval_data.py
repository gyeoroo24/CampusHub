"""Generate labelled Buy & Sell posts for testing automatic flagging (app/screening.py).

    python scripts/generate_auto_flag_eval_data.py

Writes two files, both reproducible from a fixed seed:
  tests/data/auto_flag_eval.csv  one listing per row: title, gold_prohibited, gold_gibberish, tier, source
  tests/data/spam_eval.json      spam scenarios: the seller's earlier posts (text, posted within the last
                                 hour or not) and the new post, with gold_spam

Tiers:
  prohibited  an item that can't be sold on campus (drugs, alcohol, tobacco, weapons, fake documents,
              leaked papers, counterfeits, stolen goods, fireworks, paid exam or assignment writing).
              Some use slang and no banned word, so only the similarity check can catch them.
  lookalike   harmless items that sound close to a prohibited one (water bottles, toy guns, kitchen knives,
              beer mugs, previous-year papers, medicine boxes, phones with bills). These must not be flagged.
  clean       ordinary listings, taken from the category test set (real-looking titles across categories).
  gibberish   keyboard runs, repeated letters, consonant clusters, random strings.
  real        short real titles with brands, models or numbers, which the gibberish check must pass.

Labels come from the generator and were not reviewed by a person. The titles are synthetic.
"""
import csv
import json
import pathlib
import random

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA = ROOT / "tests" / "data"
CATEGORY_CSV = DATA / "category_suggest_eval.csv"
SEED = 20261103

PROHIBITED = {
    "drugs": (["ganja", "weed", "MDMA pills", "cocaine", "LSD blotters", "charas", "hash", "magic mushrooms",
               "ecstasy tablets", "heroin"],
              ["10g packet", "good quality", "from goa", "available tonight", "DM for price", "100% pure", "bulk order",
               "", ""]),
    "drugs_slang": (["green stuff", "the white powder", "party stuff 2 grams", "smoke pack", "bhang laddoo",
                     "kaali", "pinch of happiness", "tripping paper"],
                    ["available", "good stuff", "DM me", "fresh stock", "cheap", ""]),
    "alcohol": (["Old Monk rum", "whisky bottle", "vodka 750ml", "beer case", "wine bottle", "tequila", "liquor bottle"],
                ["sealed", "with bill", "for party", "cheap", "unopened", "", ""]),
    "tobacco": (["cigarettes pack", "vape pen", "e-cigarette", "gutka box", "hookah flavour", "cigar box"],
                ["sealed", "new", "bulk", ""]),
    "weapons": (["pistol", "revolver", "combat knife", "dagger", "sword", "bullets 9mm", "hunting rifle",
                 "brass knuckles"],
                ["for sale", "licensed", "good condition", "", ""]),
    "fake_docs": (["fake ID card", "forged marksheet", "fake degree certificate", "fake bonafide certificate",
                   "duplicate passport"],
                  ["urgent", "good quality", "quick delivery", ""]),
    "leaked_papers": (["leaked end sem question paper", "answer key of mid sem", "GATE 2026 question paper leak",
                       "exam paper leak before exam"],
                      ["for sale", "DM", "pdf", ""]),
    "counterfeit": (["first copy Rolex", "replica Nike shoes", "fake branded watch", "counterfeit iPhone"],
                    ["best quality", "at half price", "", ""]),
    "stolen": (["phone without bill, no questions", "stolen laptop", "gold chain no bill from hostel room"],
               ["cheap", "urgent", "", ""]),
    "fireworks": (["crackers box", "firecrackers bulk", "explosives", "fireworks for diwali"],
                  ["cheap", "bulk", "", ""]),
    "services": (["will write your assignment for money", "I'll write your exam paper", "take exam on your behalf",
                  "paid thesis writing"],
                 ["DM", "any subject", "", ""]),
}

LOOKALIKE = [
    "Milton water bottle {size}", "steel sipper {size}", "hydration flask {size}", "glass water bottle {size}",
    "toy gun for kids", "nerf blaster toy", "water gun toy", "toy sword for kids",
    "kitchen knife set", "chef knife {size}", "vegetable cutter", "butter knife set", "swiss army knife style multitool",
    "beer mug glass set", "coffee mug ceramic", "bar counter wine glasses set",
    "previous year papers bundle (solved)", "GATE CS previous papers", "old question papers for practice",
    "first aid kit", "medicine box empty", "pill organizer box",
    "wristwatch Casio", "phone with bill and box", "Redmi phone with bill", "stolen-proof bike lock",
    "artificial plant decor", "fake plant pot", "glass bottle decor", "perfume bottle empty", "laptop with bill",
    "cricket bat with bill", "gas lighter for camping", "pressure cooker {size}", "fire extinguisher mini",
]

GIBBERISH = ["asdfgh", "qwerty", "zxcvbn", "hjkl sdfg", "poiuyt", "asdfghjkl", "ghjkl",
             "aaaaaa", "xxxxxxx", "hhhhhhhh", "oooooooo",
             "bcdfgh", "hbhbbkh", "xkcdzzzz", "gzrtpq", "ptkhrsmq", "vrmnlk",
             "j8sk2l", "kdjfl938", "qzxw ppk", "mnbvcx", "zq1 xv7", "jjjjjj", "musssiiccc"]

REAL = ["Btwin Rockrider ST20", "Haier fridge", "Yonex Muscle Power", "1st floor", "Macbook", "iPhone 12",
        "HC Verma physics vol 1", "Cormen algorithms", "Prestige 3L cooker", "LED desk lamp", "XL hoodie",
        "Hero Sprint 26T", "Nilkamal chair", "Kindle Paperwhite", "Lenovo T480", "Philips iron",
        "Samsung 27 inch monitor", "Casio fx-991ES", "JBL Tune 510BT", "Logitech MK270", "Atlas cycle",
        "Usha table fan", "Godrej almirah", "Kent RO", "Sony WH-CH520", "TP-Link router"]

# Held-out drug slang: terms NOT used when the slang rules were written, so this group measures generalisation.
HELDOUT_SLANG = (["dope packet 2g", "molly 1g pure", "edibles chocolate bar 100mg", "stash for party tonight",
                  "pot bag cheap", "hash brownie box", "blow 1 gram", "ketamine vial", "crack rock 1g",
                  "DMT cartridge", "xanax strip", "nitrous balloons"],
                 ["DM", "fresh", "best price", "for party", "", ""])

SIZES = ["1L", "500ml", "750ml", "2L", "size M", "1 litre"]
SPAM_ITEMS = ["Hero Sprint cycle for sale", "Yonex badminton racket", "Study table with drawer", "Milton flask 1L",
              "Casio keyboard CT-S300", "Dell laptop charger", "Nike shoes size 9", "Physics textbook 2nd year"]


def noisy(text: str, rng: random.Random) -> str:
    roll = rng.random()
    if roll < 0.10:
        return text.lower()
    if roll < 0.16 and len(text) > 4:
        i = rng.randrange(len(text) - 1)
        return text[:i] + text[i + 1] + text[i] + text[i + 2:]
    if roll < 0.20:
        return text.upper()
    return text


def join(*parts: str) -> str:
    return " ".join(p for p in parts if p).strip()


def prohibited_rows(rng: random.Random, per_group: int = 14):
    rows = []
    for group, (nouns, extras) in PROHIBITED.items():
        seen = set()
        while len(seen) < per_group:
            title = noisy(join(rng.choice(nouns), rng.choice(extras)), rng)
            if title.lower() in seen:
                continue
            seen.add(title.lower())
            rows.append({"title": title, "gold_prohibited": 1, "gold_gibberish": 0,
                         "tier": "prohibited", "source": f"generated:{group}"})
    return rows


def lookalike_rows(rng: random.Random, n: int = 90):
    rows, seen = [], set()
    while len(rows) < n:
        title = rng.choice(LOOKALIKE).format(size=rng.choice(SIZES))
        if rng.random() < 0.3:
            title = join(title, rng.choice(["almost new", "with bill", "negotiable", "1 year old", ""]))
        title = noisy(title, rng)
        if title.lower() in seen:
            continue
        seen.add(title.lower())
        rows.append({"title": title, "gold_prohibited": 0, "gold_gibberish": 0,
                     "tier": "lookalike", "source": "generated"})
    return rows


def clean_rows(rng: random.Random, n: int = 220):
    with CATEGORY_CSV.open(newline="") as f:
        titles = [r["title"] for r in csv.DictReader(f)]
    picked = rng.sample(titles, min(n, len(titles)))
    return [{"title": t, "gold_prohibited": 0, "gold_gibberish": 0, "tier": "clean", "source": "category test set"}
            for t in picked]


def gibberish_rows(rng: random.Random):
    rows = [{"title": g, "gold_prohibited": 0, "gold_gibberish": 1, "tier": "gibberish",
             "source": "hand-written"} for g in GIBBERISH]
    while len(rows) < 80:   # random keyboard-like strings, the same length range as real junk
        n = rng.randint(5, 10)
        s = "".join(rng.choice("bcdfghjklmnpqrstvwxzaeiou0123456789") for _ in range(n))
        rows.append({"title": s, "gold_prohibited": 0, "gold_gibberish": 1, "tier": "gibberish",
                     "source": "generated"})
    return rows


def real_rows():
    return [{"title": t, "gold_prohibited": 0, "gold_gibberish": 0, "tier": "real", "source": "hand-written"}
            for t in REAL]


def spam_scenarios(rng: random.Random):
    """Each scenario: the seller's posts in the last 24 h (minutes ago, text) and the new post."""
    out = []

    def add(kind, history, new, gold):
        out.append({"kind": kind, "history": history, "title": new, "gold_spam": int(gold)})

    for item in SPAM_ITEMS:
        # Same item posted again: 2 earlier posts in the last day -> the third is spam.
        add("repeat_identical", [{"minutes_ago": rng.randint(120, 1300), "text": item} for _ in range(2)], item, True)
        add("repeat_case_punct", [{"minutes_ago": rng.randint(120, 1300), "text": item.lower() + "!!"},
                                  {"minutes_ago": rng.randint(120, 1300), "text": item.upper()}], item, True)
        # Only one earlier post of the same item: not spam yet.
        add("repeat_once", [{"minutes_ago": rng.randint(120, 1300), "text": item}], item, False)
        # Different items are never spam, even from the same seller.
        others = [x for x in SPAM_ITEMS if x != item]
        add("different_items", [{"minutes_ago": rng.randint(120, 1300), "text": o} for o in rng.sample(others, 3)],
            item, False)
    # Burst: 8 earlier posts in the last hour -> a ninth is spam; 7 earlier is not.
    for i in range(12):
        new = f"{rng.choice(REAL)} variant {i}"
        burst = [{"minutes_ago": rng.randint(1, 55), "text": f"Item {k} for sale {rng.randint(100, 999)}"}
                 for k in range(8)]
        add("burst_8_in_hour", burst, new, True)
        add("burst_7_in_hour", burst[:7], new, False)
    # Paraphrases of the same item: the model's similarity catches some of them.
    paraphrases = [("Hero Sprint cycle for sale", "Hero Sprint cycle, selling now"),
                   ("Study table with drawer", "study table with a drawer for sale"),
                   ("Casio keyboard CT-S300", "casio CT-S300 keyboard for sale"),
                   ("Nike shoes size 9", "Nike running shoes size 9 for sale")]
    for a, b in paraphrases:
        add("paraphrase_repeat", [{"minutes_ago": 300, "text": a}, {"minutes_ago": 500, "text": a}], b, True)
    # Honest negatives: earlier posts from another day (outside 24 h) are not in the history at all.
    add("old_posts_ignored", [], SPAM_ITEMS[0], False)
    rng.shuffle(out)
    return out


def heldout_slang_rows(seed: int = SEED + 1, n: int = 60):
    """Held-out slang, from its own seed, appended after the main rows so those stay identical."""
    rng = random.Random(seed)
    nouns, extras = HELDOUT_SLANG
    rows, seen = [], set()
    while len(rows) < n:
        title = noisy(join(rng.choice(nouns), rng.choice(extras)), rng)
        if title.lower() in seen:
            continue
        seen.add(title.lower())
        rows.append({"title": title, "gold_prohibited": 1, "gold_gibberish": 0,
                     "tier": "prohibited", "source": "generated:drugs_slang_heldout"})
    return rows


def main() -> None:
    rng = random.Random(SEED)
    rows = prohibited_rows(rng) + lookalike_rows(rng) + clean_rows(rng) + gibberish_rows(rng) + real_rows()
    rng.shuffle(rows)
    rows += heldout_slang_rows()
    DATA.mkdir(parents=True, exist_ok=True)
    with (DATA / "auto_flag_eval.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["title", "gold_prohibited", "gold_gibberish", "tier", "source"])
        w.writeheader()
        w.writerows(rows)
    spam = spam_scenarios(rng)
    (DATA / "spam_eval.json").write_text(json.dumps(spam, indent=1))
    print(f"wrote {len(rows)} listings to {DATA / 'auto_flag_eval.csv'}")
    print(f"wrote {len(spam)} spam scenarios to {DATA / 'spam_eval.json'}")


if __name__ == "__main__":
    main()
