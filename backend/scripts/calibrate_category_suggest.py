"""Measure category suggestion (app/categories_suggest.py) on labelled titles, to pick its thresholds.

    python scripts/calibrate_category_suggest.py

Needs the model (scripts/fetch_match_models.py --suggest-only). Uses the same rank() as the API,
with each category's "recent listings" taken from EXAMPLES below (real titles from the local seed
data) instead of the database. Two settings are scored: all categories present, and Plant and
Musical Instruments removed (titles that only fit those must then get no suggestion).
Prints how often the top pick is right, then the threshold / margin that gives the most right
suggestions while counting each wrong one double; the chosen values live in app/config.py.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from app.categories_suggest import BgeEmbedder, pick, rank  # noqa: E402
from app.matching.trigger import model_dir  # noqa: E402

# Gold = the acceptable categories; empty = nothing fits, so the suggester should stay quiet.
CATS = ["Books", "Electronics", "Cycles", "Furniture", "Clothing", "Kitchen & Appliances",
        "Sports & Fitness", "Stationery", "Plant", "Bottle", "Musical Instruments"]

E = set()
TITLES = [
    # Books
    ("HC Verma Concepts of Physics vol 1", {"Books"}), ("Elements of Statistical Learning", {"Books"}),
    ("Cormen algorithms textbook", {"Books"}), ("Harry Potter box set", {"Books"}),
    ("GRE prep guide Manhattan 5lb", {"Books"}), ("novel", {"Books"}), ("Thermodynamics by Cengel", {"Books"}),
    ("used textbooks for 1st sem", {"Books"}),
    # Electronics
    ("JBL Tune 510BT headphones", {"Electronics"}), ("Lenovo ThinkPad T480", {"Electronics"}),
    ("iPhone 12 64GB", {"Electronics"}), ("Samsung 27 inch monitor", {"Electronics"}),
    ("power bank 20000mAh", {"Electronics"}), ("Arduino Uno with sensors", {"Electronics"}),
    ("HDMI cable 2m", {"Electronics"}), ("wireless mouse", {"Electronics"}), ("laptop", {"Electronics"}),
    ("Kindle Paperwhite", {"Electronics", "Books"}), ("Casio fx-991EX calculator", {"Electronics", "Stationery"}),
    ("table lamp LED", {"Electronics", "Furniture"}), ("Mi smart band 6", {"Electronics", "Sports & Fitness"}),
    # Cycles
    ("Hero Sprint geared bicycle", {"Cycles"}), ("Btwin MTB 21 speed", {"Cycles"}), ("cycle lock and chain", {"Cycles"}),
    ("ladies bicycle with basket", {"Cycles"}), ("bike", {"Cycles"}), ("Firefox Road Runner", {"Cycles"}),
    # Furniture
    ("study table", {"Furniture"}), ("used study table", {"Furniture"}), ("plastic chair", {"Furniture"}),
    ("bookshelf 4 tier", {"Furniture"}), ("bean bag XXL", {"Furniture"}), ("foldable bed", {"Furniture"}),
    ("mattress 6x3", {"Furniture"}), ("wooden cupboard", {"Furniture"}), ("pillow and bedsheet", {"Furniture", "Clothing"}),
    # Clothing
    ("Nike running shoes size 9", {"Clothing", "Sports & Fitness"}), ("winter sweater", {"Clothing"}),
    ("raincoat", {"Clothing"}), ("kurta for convocation", {"Clothing"}), ("lab coat", {"Clothing"}),
    ("jeans 32 waist", {"Clothing"}), ("hoodie", {"Clothing"}),
    # Kitchen & Appliances
    ("electric kettle", {"Kitchen & Appliances"}), ("Philips mixer grinder", {"Kitchen & Appliances"}),
    ("microwave oven 20L", {"Kitchen & Appliances"}), ("pressure cooker 3L", {"Kitchen & Appliances"}),
    ("table fan Usha", {"Kitchen & Appliances", "Electronics"}), ("iron box", {"Kitchen & Appliances", "Electronics"}),
    ("water heater immersion rod", {"Kitchen & Appliances", "Electronics"}), ("utensils set", {"Kitchen & Appliances"}),
    # Sports & Fitness
    ("badminton racket Yonex", {"Sports & Fitness"}), ("football size 5", {"Sports & Fitness"}),
    ("gym gloves", {"Sports & Fitness"}), ("skipping rope", {"Sports & Fitness"}), ("chess board", {"Sports & Fitness"}),
    ("tennis balls pack", {"Sports & Fitness"}), ("swimming goggles", {"Sports & Fitness"}),
    # Stationery
    ("A4 sheets ream", {"Stationery"}), ("geometry box", {"Stationery"}), ("fountain pen", {"Stationery"}),
    ("whiteboard markers", {"Stationery"}), ("spiral notebooks", {"Stationery"}), ("drafter", {"Stationery"}),
    # Plant
    ("plant", {"Plant"}), ("money plant in a pot", {"Plant"}), ("succulents", {"Plant"}), ("tulsi sapling", {"Plant"}),
    ("aloe vera", {"Plant"}), ("bonsai", {"Plant"}),
    # Bottle
    ("Milton water bottle 1L", {"Bottle"}), ("steel flask", {"Bottle"}), ("sipper", {"Bottle"}),
    ("Tupperware bottle", {"Bottle"}),
    # Musical instruments
    ("acoustic guitar Yamaha", {"Musical Instruments"}), ("keyboard Casio CT-S300", {"Musical Instruments", "Electronics"}),
    ("ukulele", {"Musical Instruments"}), ("tabla set", {"Musical Instruments"}), ("flute", {"Musical Instruments"}),
    # Nothing fits
    ("room on rent near campus", E), ("selling my notes service", E), ("asdfgh", E), ("hello", E),
    ("car pooling to airport", E), ("perfume", E), ("umbrella", E), ("suitcase trolley", E),
]

# Abstention when the right category doesn't exist: drop these categories, and these titles must get None.
MISSING_CATS = {"Plant", "Musical Instruments"}

EXAMPLES = {
    "Books": ["Linear Algebra and Its Applications - Strang", "Introduction to Algorithms (CLRS), 3rd ed",
              "GATE CS previous papers bundle", "Pattern Recognition and ML - Bishop", "Deep Learning - Goodfellow et al.",
              "Convex Optimization - Boyd & Vandenberghe"],
    "Electronics": ["Dell 24-inch monitor (P2419H)", "Logitech MK270 keyboard and mouse", "Laptop stand (aluminium)",
                    "Raspberry Pi 4 (4GB) kit", "Sony WH-CH520 headphones", "Macbook", "TP-Link Archer C6 router",
                    "Extension board with surge protection", "Casio fx-991ES Plus calculator"],
    "Cycles": ["Hero Sprint 26T cycle", "Firefox Bad Attitude 26T", "Btwin Rockrider ST20", "Hercules Roadeo A50",
               "Atlas Lady Bird cycle", "Old Hero Jet cycle"],
    "Furniture": ["Single-bed mattress (Sleepwell)", "Ergonomic office chair", "Study table with drawer"],
    "Kitchen & Appliances": ["Room cooler (Bajaj)", "Mini fridge (Haier 50L)", "Rice cooker 1.8L", "Prestige induction cooktop"],
    "Sports & Fitness": ["Dumbbell set 2 x 5kg", "SG cricket bat (English willow)", "Yoga mat 6mm",
                         "Yonex Muscle Power badminton racquet"],
    "Clothing": ["Winter jacket (M)", "Formal blazer (40)", "Lab coat (L)"],
    "Stationery": ["Drafting kit and A2 drawing board", "Pack of 10 long notebooks"],
    "Plant": ["Very important Plant"],
    "Bottle": ["Milton Thermosteel Flask 1000ml"],
}


def outcomes(rankings, cats, threshold, margin):
    right = wrong = silent = false_on_none = 0
    for (title, gold), ranked in zip(TITLES, rankings):
        gold = gold & set(cats)
        choice = pick(ranked, threshold, margin)
        if not gold:
            false_on_none += choice is not None
        elif choice is None:
            silent += 1
        elif choice[1] in gold:
            right += 1
        else:
            wrong += 1
    return right, wrong, silent, false_on_none


def main() -> None:
    emb = BgeEmbedder(model_dir())
    settings = {}
    for label, cats in (("all categories", CATS), ("Plant, Musical Instruments removed",
                                                    [c for c in CATS if c not in MISSING_CATS])):
        categories = list(enumerate(cats))
        examples = {i: EXAMPLES[c] for i, c in categories if c in EXAMPLES}
        settings[label] = (cats, [rank(emb, t, categories, examples) for t, _ in TITLES])
    cats, rankings = settings["all categories"]
    top = sum(r[0][1] in g for (t, g), r in zip(TITLES, rankings) if g)
    print(f"top pick right: {top}/{sum(1 for _, g in TITLES if g)}")
    best = None
    for threshold in np.arange(0.30, 0.80, 0.01):
        for margin in (0, 0.01, 0.02, 0.03, 0.05, 0.08):
            a = outcomes(rankings, cats, threshold, margin)
            b = outcomes(*reversed(settings["Plant, Musical Instruments removed"]), threshold, margin)
            utility = a[0] - 2 * (a[1] + a[3] + b[1] + b[3])
            if best is None or utility > best[0]:
                best = (utility, threshold, margin, a, b)
    _, threshold, margin, a, b = best
    print(f"best threshold {threshold:.2f}, margin {margin:.2f}")
    print(f"  all categories:      right {a[0]}, wrong {a[1]}, silent {a[2]}, suggested for 'nothing fits' {a[3]}")
    print(f"  with two removed:    wrong {b[1]}, suggested when the right one is missing {b[3]}")


if __name__ == "__main__":
    main()
