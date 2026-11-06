"""Generate labelled titles for testing category suggestion (app/categories_suggest.py).

    python scripts/generate_category_eval_data.py

Writes tests/data/category_suggest_eval.csv (columns: title, gold, tier, source). `gold` lists the
acceptable categories separated by "|"; it is empty when no category fits (the suggester must stay quiet).

Tiers:
  easy   the category name or a common product word appears in the title
  hard   the title names a brand, model or synonym, so the category has to be inferred
  none   nothing fits, or the right category is not in the suggester's category list
Titles are generated from templates with a fixed seed, so the file is reproducible. Labels come from
the generator, not from human review: treat the accuracy numbers as a regression check on this
synthetic set, not as an estimate for real listings.
"""
import csv
import pathlib
import random

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "tests" / "data" / "category_suggest_eval.csv"
SEED = 20261102
PER_CATEGORY = 30   # generated easy titles per category (plus the hard ones below)

# Buy & Sell categories in the calibration set (the "base" list).
BASE = {
    "Books": ["textbook", "reference book", "guide", "paperback", "question bank", "novel", "notes", "hardcover"],
    "Electronics": ["laptop", "monitor", "keyboard", "wireless mouse", "headphones", "earbuds", "power bank",
                    "router", "hard disk", "pendrive", "webcam", "bluetooth speaker", "tablet", "smartwatch"],
    "Cycles": ["bicycle", "cycle", "MTB", "road bike", "geared cycle", "folding cycle", "kids cycle", "bike"],
    "Furniture": ["study table", "office chair", "bookshelf", "bed frame", "sofa", "wardrobe", "dining table",
                  "bean bag", "mattress", "shoe rack", "computer table", "recliner"],
    "Clothing": ["jacket", "hoodie", "kurta", "jeans", "blazer", "saree", "lab coat", "sweater", "track pants",
                 "t-shirt", "raincoat", "formal shirt"],
    "Kitchen & Appliances": ["electric kettle", "mixer grinder", "microwave oven", "induction cooktop", "rice cooker",
                             "toaster", "water purifier", "pressure cooker", "air fryer", "mini fridge", "room heater"],
    "Sports & Fitness": ["cricket bat", "badminton racquet", "football", "tennis ball", "yoga mat", "dumbbells",
                         "skipping rope", "gym gloves", "chess board", "carrom board", "swimming goggles", "hockey stick"],
    "Stationery": ["A4 ream", "geometry box", "fountain pen", "whiteboard markers", "spiral notebook", "drafter",
                   "stapler", "highlighter set", "file folder", "sticky notes", "graph paper pad", "pencil box"],
    "Plant": ["money plant", "succulent", "snake plant", "tulsi sapling", "aloe vera", "bonsai", "cactus",
              "peace lily", "potted fern", "bamboo plant"],
    "Bottle": ["steel water bottle", "sipper", "thermos flask", "sports bottle", "steel flask", "glass bottle"],
    "Musical Instruments": ["acoustic guitar", "keyboard piano", "ukulele", "tabla", "harmonium", "flute", "violin",
                            "electric guitar", "drum set", "cajon"],
}

# Categories added only for this evaluation (never written to the database).
EXTRA = {
    "Pet Supplies": ["dog leash", "cat litter tray", "pet bed", "bird cage", "fish tank", "dog food bowl",
                     "pet carrier", "cat scratcher"],
    "Garden Tools": ["spade", "pruning shears", "garden hose", "lawn mower", "watering can", "garden rake",
                     "wheelbarrow", "hedge trimmer"],
    "Board Games": ["Monopoly", "Scrabble", "Catan", "Uno cards", "Ludo board", "jigsaw puzzle 1000 pieces",
                    "Pictionary", "Jenga"],
    "Art Supplies": ["watercolor set", "acrylic paints", "canvas board", "sketch pad", "oil pastels",
                     "paint brush set", "easel", "charcoal sticks"],
    "Toys": ["remote control car", "lego set", "teddy bear", "doll house", "toy train", "building blocks",
             "action figure", "rocking horse"],
}

# Brands are drawn only from the category they belong to, so a brand never points at a wrong category.
# Most titles get no brand at all.
BRAND_POOL = {
    "Electronics": ["Dell", "HP", "Lenovo", "boAt", "JBL", "Logitech", "Samsung", "Sony", "TP-Link", "Zebronics"],
    "Cycles": ["Hero", "Firefox", "Hercules", "Btwin", "Atlas", "Avon"],
    "Sports & Fitness": ["Yonex", "Nivia", "Cosco", "Decathlon", "Cosco"],
    "Kitchen & Appliances": ["Philips", "Prestige", "Bajaj", "Usha", "Kent", "Morphy Richards"],
    "Bottle": ["Milton", "Cello", "Borosil"],
    "Musical Instruments": ["Yamaha", "Casio", "Roland", "Hohner"],
    "Furniture": ["Godrej", "Nilkamal", "Sleepwell"],
    "Clothing": ["Levis", "Allen Solly", "Puma"],
    "Stationery": ["Camlin", "Faber-Castell", "Cello", "Reynolds"],
    "Books": ["Pearson", "McGraw Hill", "Oxford"],
    "Plant": [],
    "Pet Supplies": ["Pedigree", "Whiskas", "Trixie"],
    "Garden Tools": ["Fiskars", "Honda", "Stanley"],
    "Board Games": ["Hasbro", "Ravensburger", "Cosco"],
    "Art Supplies": ["Camlin", "Faber-Castell", "Bon Ami"],
    "Toys": ["Hamleys", "Funskool", "Lego"],
}
MODIFIERS = ["", "", "", "used ", "new ", "good condition ", "urgent sale ", "barely used ", "imported "]
SUFFIXES = ["", "", "", " 1 year old", " almost new", " with bill", " (negotiable)", " size M", " 2 years used"]

# Hand-written hard titles: brands, models and synonyms. Tuple of (title, gold categories).
HARD = [
    ("Yamaha F310 guitar", {"Musical Instruments"}), ("Casio CT-S300 keys", {"Musical Instruments", "Electronics"}),
    ("Mi Band 6 fitness tracker", {"Electronics", "Sports & Fitness"}), ("Lenovo IdeaPad slim 3", {"Electronics"}),
    ("Usha table fan", {"Kitchen & Appliances", "Electronics"}), ("Philips Daily Collection iron", {"Kitchen & Appliances", "Electronics"}),
    ("Hercules Roadeo A50", {"Cycles"}), ("Firefox Bad Attitude 26T", {"Cycles"}),
    ("Godrej almirah 3 door", {"Furniture"}), ("Nilkamal plastic chair", {"Furniture"}),
    ("Puma running shoes size 9", {"Clothing", "Sports & Fitness"}), ("Levis 511 slim jeans", {"Clothing"}),
    ("Bajaj Majesty room heater", {"Kitchen & Appliances"}), ("Prestige induction base", {"Kitchen & Appliances"}),
    ("Kent water purifier RO", {"Kitchen & Appliances"}), ("Nivia cricket bat", {"Sports & Fitness"}),
    ("Cross ballpoint pen set", {"Stationery"}), ("Camlin colour pencils 24", {"Stationery", "Art Supplies"}),
    ("Sleepwell mattress queen", {"Furniture"}), ("Milton Thermosteel 1L", {"Bottle"}),
    ("Cello tumbler stainless", {"Bottle"}), ("Zebronics woofer speaker", {"Electronics"}),
    ("Yonex Muscle Power 29", {"Sports & Fitness"}), ("Cosco carrom striker", {"Sports & Fitness", "Board Games"}),
    ("Harry Potter box set", {"Books"}), ("Kindle Paperwhite", {"Electronics", "Books"}),
    ("HC Verma physics vol 1", {"Books"}), ("Cormen algorithms book", {"Books"}),
    ("Hamleys soft plush", {"Toys"}), ("Funskool building set", {"Toys"}),
    ("Faber-Castell watercolour tin", {"Art Supplies"}), ("Bon Ami acrylic paints", {"Art Supplies"}),
    ("Pedigree dog food bowl", {"Pet Supplies"}), ("Whiskas cat food pouch", {"Pet Supplies"}),
    ("Fiskars pruning shears", {"Garden Tools"}), ("Honda petrol lawnmower", {"Garden Tools"}),
    ("Hasbro Monopoly classic", {"Board Games"}), ("Ravensburger 1000 piece puzzle", {"Board Games"}),
]

# Titles that fit two categories: the suggester may pick either.
CROSS = [
    ("table fan", {"Kitchen & Appliances", "Electronics"}), ("iron box", {"Kitchen & Appliances", "Electronics"}),
    ("kindle", {"Electronics", "Books"}), ("calculator", {"Electronics", "Stationery"}),
    ("pillow and bedsheet", {"Furniture", "Clothing"}), ("sports shoes", {"Clothing", "Sports & Fitness"}),
    ("smart band", {"Electronics", "Sports & Fitness"}), ("digital piano", {"Musical Instruments", "Electronics"}),
    ("LED table lamp", {"Electronics", "Furniture"}), ("electric scooter", {"Electronics", "Cycles"}),
    ("water heater", {"Kitchen & Appliances", "Electronics"}), ("football boots", {"Sports & Fitness", "Clothing"}),
]

# Nothing fits: general listings, services, filler text. Also titles about categories not in the list.
NONE = [
    "room on rent near campus", "single room for girls", "2BHK flat sharing", "selling my notes service",
    "tuition for class 10 maths", "carpool to airport", "lift to Majestic", "looking for roommate",
    "free wifi hotspot", "event tickets for fest", "birthday cake order", "photography service",
    "resume writing help", "gym membership transfer", "parking spot available", "mess tiffin service",
    "asdfgh", "hello", "test123", "ok", "nice", "good morning", "xyz", "qwerty", "123", "....", "sold",
    "urgent", "free", "any offers", "DM me", "available tomorrow", "perfume", "umbrella", "suitcase trolley",
    "backpack for trekking", "sunglasses", "car seat cover", "shoe polish", "soap bar pack", "first aid kit",
    "vegetable seeds packet", "fresh flowers bouquet", "gold ring", "silver anklet", "wedding saree rental",
    "passport photo service", "old newspapers", "cardboard boxes", "sim card", "driving lessons",
]

# Lost & Found style and noisy wording, still gold-labelled, so the suggester is also tested on messy text.
NOISE_EXTRA = {
    "Bottle": ["bottle (blue, scratched cap)", "water bottle near canteen"],
    "Electronics": ["black laptop charger lost near library", "earphones left in lab"],
    "Books": ["notebook with maths notes found"],
}


def noisy(text: str, rng: random.Random) -> str:
    """Realistic typing noise: case changes, a swapped letter pair, or a dropped space."""
    roll = rng.random()
    if roll < 0.12:
        return text.lower()
    if roll < 0.20 and len(text) > 4:
        i = rng.randrange(len(text) - 1)
        return text[:i] + text[i + 1] + text[i] + text[i + 2:]
    if roll < 0.24:
        return text.replace(" ", "", 1)
    return text


def generated(categories: dict[str, list[str]], rng: random.Random) -> list[tuple[str, set[str], str]]:
    rows = []
    for cat, nouns in categories.items():
        seen = set()
        while len(seen) < PER_CATEGORY:
            brands = BRAND_POOL.get(cat, []) + [""] * 3   # about one title in three names a brand
            title = (rng.choice(brands) + " " + rng.choice(MODIFIERS) + rng.choice(nouns) + rng.choice(SUFFIXES)).strip()
            title = " ".join(title.split())
            if title.lower() in seen:
                continue
            seen.add(title.lower())
            rows.append((noisy(title[0].upper() + title[1:] if rng.random() < 0.6 else title, rng), {cat}, "easy"))
    return rows


def main() -> None:
    rng = random.Random(SEED)
    rows = generated(BASE, rng) + generated(EXTRA, rng)
    rows += [(t, g, "hard" if g else "none") for t, g in HARD]
    rows += [(t, g, "hard") for t, g in CROSS]
    rows += [(t, set(), "none") for t in NONE]
    rows += [(t, {c}, "hard") for c, ts in NOISE_EXTRA.items() for t in ts]

    rng.shuffle(rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["title", "gold", "tier", "source"])
        for title, gold, tier in rows:
            source = "generated" if tier == "easy" else "hand-written"
            w.writerow([title, "|".join(sorted(gold)), tier, source])
    print(f"wrote {len(rows)} rows to {OUT}")


if __name__ == "__main__":
    main()
