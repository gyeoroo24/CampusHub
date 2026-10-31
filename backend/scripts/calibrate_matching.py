"""Measure the similarity scores the Lost & Found matcher sees, to pick its thresholds.

    python scripts/calibrate_matching.py <photo_dir> [model_dir]

photo_dir holds photos named <kind>_<n>.jpg (e.g. wallet_0.jpg, wallet_1.jpg), a few per kind of
item. Prints, for each signal, the scores of true pairs and of wrong pairs, plus the latency. The
chosen ranges live in app/matching/engine.py (SIGNALS); rerun this after changing a model.
"""
import pathlib
import statistics
import sys
import time

import numpy as np
from PIL import Image, ImageEnhance

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from app.config import get_settings  # noqa: E402
from app.matching.engine import score_pair  # noqa: E402
from app.matching.models import OnnxEmbedder  # noqa: E402

# (kind, lost description, found description written by someone else about the same item)
PAIRS = [
    ("earbuds", "Lost my black JBL wireless earbuds in a small charging case near the library",
     "Found wireless earphones in a black case on a library reading table"),
    ("bottle", "Blue Milton steel water bottle with stickers, left in CDS lecture hall 102",
     "Found a steel bottle (blue, lots of stickers) in lecture hall 102"),
    ("charger", "Grey HP laptop charger, 65W, forgot it at the main canteen",
     "Found a laptop power adapter, HP, at the canteen"),
    ("idcard", "Lost my IISc ID card, name Kavya Bhat, somewhere between hostel and gymkhana",
     "Found an ID card near the gymkhana, belongs to a student"),
    ("wallet", "Brown leather wallet with some cash and a Canara bank card",
     "Found a brown wallet near the main gate"),
    ("calculator", "Casio fx-991EX scientific calculator lost after the exam in the Physics building",
     "Calculator (Casio) found in physics department exam hall"),
    ("keys", "Black Hero Sprint cycle key on a red keychain",
     "Found a single key with a red key chain near the cycle stand"),
    ("glasses", "Pair of round black-framed spectacles in a blue case",
     "Spectacles in a blue case found on a bench"),
    ("backpack", "Green North Face backpack with notebooks inside, near the bus stop",
     "Found a green backpack at the bus stop"),
    ("watch", "Silver Titan analog wristwatch with a metal strap",
     "Found a men's watch, silver, metal band"),
    ("phone", "Lost my Redmi Note 12 phone, blue back cover, cracked screen corner",
     "Found a mobile phone with a blue cover and a cracked screen near the mess"),
    ("umbrella", "Black folding umbrella with a wooden handle, left at the CV Raman auditorium",
     "Found a black umbrella, wooden handle, in the auditorium"),
    ("earbuds", "Lost white AirPods Pro case, has my initials SK scratched on it",
     "White earbuds case with letters scratched on the back, found in the gym"),
    ("bottle", "Transparent Tupperware water bottle with a purple lid",
     "Found a clear plastic bottle, purple cap, at the badminton court"),
    ("wallet", "Black Wildcraft fabric wallet with velcro, has my driving licence",
     "Found a black cloth wallet with velcro near the ATM"),
    ("keys", "Bunch of 3 hostel keys on a Bangalore FC keychain",
     "Three keys on a football club keyring, found at the hostel gate"),
    ("calculator", "Lost a Casio fx-82MS calculator with my name written in marker on the back",
     "Casio calculator with a name written on the back, found in LHC"),
    ("watch", "Black Fastrack digital watch, rubber strap, lost at the swimming pool",
     "Found a black digital sports watch near the pool changing room"),
    ("backpack", "Grey Skybags laptop bag with a Dell laptop inside",
     "Found a grey laptop backpack with a laptop in it, at the library entrance"),
    ("glasses", "Ray-Ban sunglasses, black frame, lost on the walk to Prakruthi",
     "Black sunglasses found near Prakruthi cafe"),
]
# Different items that sound alike: these must stay below the "possible" bar.
HARD_NEGATIVES = [
    ("Brown leather wallet with some cash and a Canara bank card",
     "Found a black cloth wallet with velcro near the ATM"),
    ("Lost my black JBL wireless earbuds in a small charging case near the library",
     "Found over-ear headphones, black, in the music room"),
    ("Blue Milton steel water bottle with stickers, left in CDS lecture hall 102",
     "Found a clear plastic bottle, purple cap, at the badminton court"),
    ("Silver Titan analog wristwatch with a metal strap",
     "Found a black digital sports watch near the pool changing room"),
    ("Grey HP laptop charger, 65W, forgot it at the main canteen",
     "Found a phone charger cable, white, in the canteen"),
    ("Casio fx-991EX scientific calculator lost after the exam in the Physics building",
     "Found a geometry box with a ruler and compass in the physics building"),
    ("Green North Face backpack with notebooks inside, near the bus stop",
     "Found a grey laptop backpack with a laptop in it, at the library entrance"),
    ("Pair of round black-framed spectacles in a blue case",
     "Black sunglasses found near Prakruthi cafe"),
]


def other_photo(img: Image.Image) -> Image.Image:
    """Stand-in for a second photo of the same item: new crop, angle, light, size."""
    w, h = img.size
    img = img.crop((int(w * .08), int(h * .05), int(w * .95), int(h * .9))).rotate(8, expand=True)
    img = ImageEnhance.Brightness(img).enhance(1.25)
    img = ImageEnhance.Color(img).enhance(0.8)
    return img.resize((img.width * 3 // 4, img.height * 3 // 4))


def jpeg(img: Image.Image) -> bytes:
    import io
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=90)
    return buf.getvalue()


def show(name: str, right: list[float], wrong: list[float], hard: list[float] | None = None) -> None:
    def q(xs):
        xs = sorted(xs)
        return f"min {xs[0]:.2f}  median {statistics.median(xs):.2f}  max {xs[-1]:.2f}  (n={len(xs)})"
    print(f"\n{name}\n  true pairs   {q(right)}\n  wrong pairs  {q(wrong)}")
    if hard:
        print(f"  look-alikes  {q(hard)}")


def main() -> None:
    photo_dir = pathlib.Path(sys.argv[1])
    model_dir = sys.argv[2] if len(sys.argv) > 2 else pathlib.Path(__file__).resolve().parents[1] / "models"
    emb = OnnxEmbedder(model_dir)

    # Description vs description (MiniLM)
    t = time.perf_counter()
    lost = np.array([emb.text(p[1]) for p in PAIRS])
    timing_text = (time.perf_counter() - t) * 1000 / len(PAIRS)
    found = np.array([emb.text(p[2]) for p in PAIRS])
    sims = lost @ found.T
    n = len(PAIRS)
    same_kind = np.array([[PAIRS[i][0] == PAIRS[j][0] for j in range(n)] for i in range(n)])
    hard = [float(np.dot(emb.text(a), emb.text(b))) for a, b in HARD_NEGATIVES]
    show("description vs description (MiniLM)", list(np.diag(sims)), list(sims[~same_kind]), hard)
    print(f"  top-1 correct {int((sims.argmax(1) == np.arange(n)).sum())}/{n}")
    s = get_settings()

    def outcome(label, values, same_category):
        scores = [score_pair(v, None, None, same_category)[0] for v in values]
        strong = sum(x >= s.match_strong for x in scores)
        possible = sum(s.match_possible <= x < s.match_strong for x in scores)
        print(f"  {label:34s} strong {strong:3d}  possible {possible:3d}  hidden {len(scores) - strong - possible:3d}")
    print("  with description alone (same category for same-kind pairs):")
    outcome("true pairs", list(np.diag(sims)), True)
    outcome("look-alikes", hard, True)
    outcome("unrelated, other category", list(sims[~same_kind]), False)

    # Photo vs photo (MobileCLIP image)
    photos = sorted(photo_dir.glob("*_*.jpg"))
    kinds = [p.stem.rsplit("_", 1)[0] for p in photos]
    imgs = [Image.open(p).convert("RGB") for p in photos]
    t = time.perf_counter()
    vecs = np.array([emb.image(jpeg(i)) for i in imgs])
    timing_photo = (time.perf_counter() - t) * 1000 / len(imgs)
    again = np.array([emb.image(jpeg(other_photo(i))) for i in imgs])
    ps = vecs @ vecs.T
    same = np.array([[kinds[i] == kinds[j] and i != j for j in range(len(kinds))] for i in range(len(kinds))])
    diff = np.array([[kinds[i] != kinds[j] for j in range(len(kinds))] for i in range(len(kinds))])
    show("photo vs photo (MobileCLIP image)",
         [float(np.dot(a, b)) for a, b in zip(vecs, again)], list(ps[diff]), list(ps[same]))
    print("  (true = a re-shot of the same photo; look-alikes = a different item of the same kind)")

    # Description vs photo (MobileCLIP text -> image)
    texts = {}
    for kind, a, b in PAIRS:
        texts.setdefault(kind, []).extend([a, b])
    right, wrong = [], []
    for kind, descs in texts.items():
        tv = np.array([emb.clip_text(d) for d in descs])
        for k, v in zip(kinds, vecs):
            (right if k == kind else wrong).extend((tv @ v).tolist())
    show("description vs photo (MobileCLIP text -> image)", right, wrong)
    print(f"\nlatency per item: description {timing_text:.1f} ms, photo {timing_photo:.1f} ms (1 thread)")


if __name__ == "__main__":
    main()
