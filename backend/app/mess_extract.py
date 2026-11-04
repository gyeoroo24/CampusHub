"""Reading a mess menu from the PDF or photo the mess committee shares, to prefill the menu form.

Nothing here is posted: the moderator checks every cell in the app, fixes what was misread, then posts.

  1. Render the page (PDF via pypdfium2, 300 dpi; photos as they are), then turn it upright: Tesseract's
     orientation check catches a table printed sideways (a landscape menu on a portrait page), and a
     small slant (a phone photo, a crooked scan) is straightened by finding the angle at which the
     table's rows line up best.
  2. Find the table's ruled lines: rows and columns where long runs of dark pixels cross the page.
  3. OCR each cell with Tesseract (Apache-2.0 LSTM OCR, no network). Tesseract is called in-process through
     libtesseract, so its language model loads once and is reused for every cell. Each cell is read in grey;
     coloured text (veg / non-veg colour coding) is easy to lose, so a weak reading is read again with the
     darkest colour channel at two thresholds and the cleanest reading kept.
  4. Find the header row (Breakfast / Lunch / Snacks / Dinner) and the weekday in each row, and turn
     the grid into menu cells. Rows below the week whose first cell is a meal ("Breakfast: tea, milk
     ...") become the notes, and so do "Daily Breakfast items: ..." lines printed under the table (D Mess);
     a title above the table ("C Mess Menu (JUNE 2026)") suggests the mess name and month. A cell's lines
     are kept apart: a line is a new dish unless it continues a wrapped name (see _join_lines), so D Mess's
     one-dish-per-line cells come out as "Dal Amritsari + Buttermilk, Seasonal Fruit, Palak Fulka".

Without ruled lines (a photo of a handwritten board, say) or without Tesseract installed, it returns
what it can and says so; the moderator types or pastes the meals instead.

numpy and Pillow are optional at import time (not every deployment ships them, e.g. a size-constrained
Lambda zip): if they're missing, extract_menu() degrades the same way it already does for a missing
Tesseract, instead of crashing the whole app at startup.
"""
from __future__ import annotations

import ctypes
import io
import os
import queue
import re
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import date

try:
    import numpy as np
    from PIL import Image, ImageOps
    _IMAGING_AVAILABLE = True
except ImportError:
    np = None  # type: ignore[assignment]
    Image = None  # type: ignore[assignment]
    ImageOps = None  # type: ignore[assignment]
    _IMAGING_AVAILABLE = False

MEALS = ("breakfast", "lunch", "snacks", "dinner")
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
MONTHS = ("january", "february", "march", "april", "may", "june", "july", "august", "september",
          "october", "november", "december")
MAX_PAGES = 3

# libtesseract, called in-process when it's installed (the Lambda layer ships it). Running the tesseract
# program for every cell loads the language model each time, which was most of the reader's run time.
_LIBRARY_NAMES = ("libtesseract.so.5", "libtesseract.5.dylib", "/opt/homebrew/lib/libtesseract.5.dylib",
                  "/usr/local/lib/libtesseract.5.dylib")
_TESSDATA_DIRS = ("/opt/share/tessdata", "/opt/homebrew/share/tessdata", "/usr/local/share/tessdata",
                  "/usr/share/tessdata")


def _load_libtesseract() -> ctypes.CDLL | None:
    for name in _LIBRARY_NAMES:
        try:
            lib = ctypes.CDLL(name)
        except OSError:
            continue
        p, i = ctypes.c_void_p, ctypes.c_int
        lib.TessBaseAPICreate.restype = p
        lib.TessBaseAPIInit3.argtypes = [p, ctypes.c_char_p, ctypes.c_char_p]
        lib.TessBaseAPIInit3.restype = i
        lib.TessBaseAPISetPageSegMode.argtypes = [p, i]
        lib.TessBaseAPISetImage.argtypes = [p, p, i, i, i, i]
        lib.TessBaseAPIGetUTF8Text.argtypes = [p]
        lib.TessBaseAPIGetUTF8Text.restype = p
        lib.TessBaseAPIGetTsvText.argtypes = [p, i]
        lib.TessBaseAPIGetTsvText.restype = p
        lib.TessDeleteText.argtypes = [p]
        lib.TessBaseAPIDetectOrientationScript.argtypes = [
            p, ctypes.POINTER(i), ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_char_p),
            ctypes.POINTER(ctypes.c_float)]
        lib.TessBaseAPIDetectOrientationScript.restype = ctypes.c_bool
        return lib
    return None


_tess = _load_libtesseract() if _IMAGING_AVAILABLE else None
_idle_engines = {"eng": queue.SimpleQueue(), "osd": queue.SimpleQueue()}


@dataclass
class Extracted:
    items: dict[tuple[int, str], str] = field(default_factory=dict)   # (weekday 1-7, meal) -> dishes
    notes: str | None = None
    mess_name: str | None = None
    month: date | None = None          # first day of the month the title names
    starts: date | None = None         # "Effective from 22/09/2026"
    warnings: list[str] = field(default_factory=list)


def ocr_available() -> bool:
    return shutil.which("tesseract") is not None


def _pages(data: bytes, content_type: str) -> list[Image.Image]:
    if content_type == "application/pdf" or data[:4] == b"%PDF":
        import pypdfium2 as pdfium
        pdf = pdfium.PdfDocument(data)
        return [pdf[i].render(scale=300 / 72).to_pil().convert("RGB") for i in range(min(len(pdf), MAX_PAGES))]
    image = Image.open(io.BytesIO(data))
    image = ImageOps.exif_transpose(image).convert("RGB")
    if image.width < 1600:   # small photos read better enlarged
        scale = 1600 / image.width
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    return [image]


def _orientation(page: Image.Image) -> int:
    """Degrees to turn the page clockwise so its text reads normally (0, 90, 180 or 270)."""
    small = page.copy()
    small.thumbnail((1600, 1600))
    if _tess is not None:
        degrees, confidence = ctypes.c_int(), ctypes.c_float()
        script, script_confidence = ctypes.c_char_p(), ctypes.c_float()
        with _engine("osd") as handle:
            _tess.TessBaseAPISetPageSegMode(handle, 0)      # 0 = orientation and script only
            _set_image(handle, _pixels(small))
            found = _tess.TessBaseAPIDetectOrientationScript(
                handle, ctypes.byref(degrees), ctypes.byref(confidence), ctypes.byref(script),
                ctypes.byref(script_confidence))
        if not found or confidence.value < 1.0:
            return 0
        return -degrees.value % 360     # the API counts the turn the other way from the program's "Rotate:" line
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        small.save(f.name)
        out = subprocess.run(["tesseract", f.name, "-", "--psm", "0"], capture_output=True, text=True, timeout=30)
    m = re.search(r"Rotate:\s*(\d+)", out.stdout + out.stderr)
    c = re.search(r"Orientation confidence:\s*([\d.]+)", out.stdout + out.stderr)
    if not m or (c and float(c.group(1)) < 1.0):
        return 0
    return int(m.group(1)) % 360


def _skew(page: Image.Image) -> float:
    """The small angle (within ±6°) that makes the table's horizontal lines straightest."""
    small = page.convert("L")
    small.thumbnail((900, 900))
    dark = (np.asarray(small) < 170).astype(np.float32)
    if dark.mean() < 0.002:
        return 0.0

    def sharpness(angle: float) -> float:
        turned = np.asarray(Image.fromarray((dark * 255).astype("uint8")).rotate(angle, fillcolor=0)) > 127
        rows = turned.sum(axis=1).astype(np.float64)
        return float(np.square(np.diff(rows)).sum())

    best = max((a / 2 for a in range(-12, 13)), key=sharpness)
    fine = max((best + a / 10 for a in range(-5, 6)), key=sharpness)
    return fine if abs(fine) >= 0.3 else 0.0


def _upright(page: Image.Image) -> Image.Image:
    turn = _orientation(page)
    if turn:
        page = page.rotate(-turn, expand=True, fillcolor="white")
    angle = _skew(page)
    if angle:
        page = page.rotate(angle, expand=True, fillcolor="white", resample=Image.BICUBIC)
    return page


def _longest_runs(mask: np.ndarray) -> np.ndarray:
    """Longest run of True along each row."""
    best = np.zeros(mask.shape[0], dtype=np.int32)
    current = np.zeros(mask.shape[0], dtype=np.int32)
    for column in mask.T:
        current = np.where(column, current + 1, 0)
        np.maximum(best, current, out=best)
    return best


def _lines(runs: np.ndarray, fraction: float, gap: int = 4) -> list[int]:
    if runs.max() == 0:
        return []
    found: list[list[int]] = []
    for i in np.where(runs > fraction * runs.max())[0]:
        if found and i - found[-1][-1] <= gap:
            found[-1].append(int(i))
        else:
            found.append([int(i)])
    return [round(sum(g) / len(g)) for g in found]


def _new_engine(lang: str) -> int:
    datadir = os.environ.get("TESSDATA_PREFIX") or next((d for d in _TESSDATA_DIRS if os.path.isdir(d)), None)
    handle = _tess.TessBaseAPICreate()
    if _tess.TessBaseAPIInit3(handle, datadir.encode() if datadir else None, lang.encode()) != 0:
        raise RuntimeError(f"Tesseract couldn't load its {lang} model")
    return handle


@contextmanager
def _engine(lang: str = "eng"):
    """An initialised Tesseract engine that no other thread is using. Engines are kept and reused, so the
    language model loads once per engine, not once per cell. Orientation needs an engine started with
    "osd": on an "eng" engine, libtesseract aborts the whole process."""
    idle = _idle_engines[lang]
    try:
        handle = idle.get_nowait()
    except queue.Empty:
        handle = _new_engine(lang)
    try:
        yield handle
    finally:
        idle.put(handle)


def _pixels(image: Image.Image) -> np.ndarray:
    return np.ascontiguousarray(np.asarray(image))


def _set_image(handle: int, pixels: np.ndarray) -> None:
    height, width = pixels.shape[:2]
    channels = 1 if pixels.ndim == 2 else pixels.shape[2]
    _tess.TessBaseAPISetImage(handle, pixels.ctypes.data, width, height, channels, pixels.strides[0])


def _tesseract_output(image: Image.Image, psm: int, tsv: bool) -> str:
    """Tesseract's text for [image], or its TSV (one row per word, with boxes) with tsv."""
    if _tess is None:
        with tempfile.NamedTemporaryFile(suffix=".png") as f:
            image.save(f.name)
            args = ["tesseract", f.name, "-", "--psm", str(psm), *(["tsv"] if tsv else [])]
            return subprocess.run(args, capture_output=True, text=True, timeout=30).stdout
    pixels = _pixels(image)
    with _engine() as handle:
        _tess.TessBaseAPISetPageSegMode(handle, psm)
        _set_image(handle, pixels)
        result = _tess.TessBaseAPIGetTsvText(handle, 0) if tsv else _tess.TessBaseAPIGetUTF8Text(handle)
        try:
            return ctypes.string_at(result).decode("utf-8")
        finally:
            _tess.TessDeleteText(result)


def _tesseract(image: Image.Image, psm: int = 6, keep_lines: bool = False):
    """The text Tesseract reads, on one line; or its lines as a list with keep_lines."""
    text = _tesseract_output(image, psm, tsv=False)
    if keep_lines:
        return [" ".join(line.split()) for line in text.splitlines() if line.strip()]
    return " ".join(text.split())


def _tesseract_lines(image: Image.Image, psm: int = 6) -> list[tuple[str, int, int]]:
    """Each line Tesseract reads, with its width and its first word's width, in pixels."""
    lines: dict[tuple, list[tuple[int, int, str]]] = {}
    for row in _tesseract_output(image, psm, tsv=True).splitlines():
        cols = row.split("\t")
        if len(cols) == 12 and cols[0] != "level" and cols[11].strip():
            left, width = int(cols[6]), int(cols[8])
            lines.setdefault((cols[2], cols[3], cols[4]), []).append((left, left + width, cols[11]))
    return [(" ".join(w for *_, w in words), words[-1][1] - words[0][0], words[0][1] - words[0][0])
            for words in lines.values()]


def _join_lines(lines: list[tuple[str, int, int]], width: int) -> str:
    """One cell's lines as one list of dishes. Menus like D Mess put each dish on its own line with no "+"
    or comma between, and long names wrap. A line continues the one before it (a wrapped name) when its
    first word wouldn't have fitted on that line, when that line ends in a connector (+ / , & -) or leaves
    a bracket open, or when this one starts with a connector, a bracket or a small letter. Otherwise it's a new dish, after
    a comma."""
    text = ""
    previous_width = 0
    for line, line_width, first_word in lines:
        if not text:
            text = line
        elif (re.search(r"[+/,&(-]$", text) or re.match(r"[+/,&()\[-]|[a-z]", line)
              or text.count("(") > text.count(")") or previous_width + first_word + 0.04 * width > 0.96 * width):
            text += " " + line
        else:
            text += ", " + line
        previous_width = line_width
    return text


def _score(text: str) -> float:
    """How much a reading looks like words: letters in words of 3+ letters, minus stray symbols."""
    tokens = re.findall(r"[A-Za-z]+", text)
    words = [t for t in tokens if len(t) >= 3 and re.search(r"[aeiouyAEIOUY]", t)]
    scraps = [t for t in tokens if len(t) <= 2 and t.lower() not in {"of", "nv", "v", "a", "&"}]
    junk = len(re.findall(r"[^\w\s,./+()&'*-]", text))
    return sum(len(w) for w in words) - 4 * len(scraps) - 3 * junk


def _read_variant(v: Image.Image, width: int) -> str:
    v = ImageOps.expand(v.resize((v.width * 2, v.height * 2), Image.LANCZOS), 30, 255)
    return _join_lines(_tesseract_lines(v), width)


def _read_cell(rgb: np.ndarray, grey: np.ndarray, box: tuple[int, int, int, int]) -> str:
    """One Tesseract call per cell in grey. A blank cell is skipped; a weak reading (coloured veg / non-veg
    text often reads badly in grey) is read again with the two colour thresholds, and the cleanest kept.
    Every read is a Tesseract call, so the reads that can be skipped are skipped."""
    x0, y0, x1, y1 = box
    crop = grey[y0:y1, x0:x1]
    if float(np.mean(crop < 170)) < 0.002:
        return ""
    width = (x1 - x0) * 2
    best = _read_variant(Image.fromarray(crop), width)
    if _score(best) < 0.5 * len(best):
        darkest = rgb[y0:y1, x0:x1].min(axis=2)
        for t in (150, 200):
            candidate = _read_variant(Image.fromarray(np.where(darkest < t, 0, 255).astype("uint8")), width)
            if _score(candidate) > _score(best):
                best = candidate
    return best


def _clean(text: str) -> str:
    text = re.sub(r"\s*([,/+])\s*", lambda m: {",": ", ", "/": " / ", "+": " + "}[m.group(1)], text)
    text = re.sub(r"[’‘`]", "/", text)                 # slashes often come out as quotes
    return " ".join(text.split()).strip(" ,.;:-|")


def _weekday(text: str) -> int | None:
    t = re.sub(r"[^a-z]", "", text.lower())
    for i, day in enumerate(WEEKDAYS):
        if len(t) >= 3 and (t.startswith(day[:3]) or day.startswith(t[:5])):
            return i + 1
    return None


def _meal(text: str) -> str | None:
    t = text.lower()
    for meal in MEALS:
        if meal[:5] in t:
            return meal
    return "snacks" if "snack" in t or "tiffin" in t else None


def _title_hints(text: str, out: Extracted) -> None:
    # "C Mess Menu", "E-Mess Menu", "North Block Mess": the word(s) before "Mess" name it.
    m = re.search(r"\b([A-Z0-9][A-Za-z0-9]{0,14}(?: [A-Z][A-Za-z0-9]{0,14})?)\s*[-–]?\s*(?i:mess)\b", text)
    if m and m.group(1).lower() not in {"the", "menu", "daily", "of"}:
        out.mess_name = f"{m.group(1)} Mess"
    d = re.search(r"(?:from|w\.?e\.?f\.?|effective)\D{0,12}(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})", text, re.IGNORECASE)
    if d:
        year = int(d.group(3)) + (2000 if len(d.group(3)) == 2 else 0)
        try:
            out.starts = date(year, int(d.group(2)), int(d.group(1)))
        except ValueError:
            pass
    months = "|".join(MONTHS)
    m = re.search(rf"({months})\W{{0,3}}(\d{{4}})", text, re.IGNORECASE)
    if m:
        out.month = date(int(m.group(2)), MONTHS.index(m.group(1).lower()) + 1, 1)


def extract_menu(data: bytes, content_type: str) -> Extracted:
    out = Extracted()
    if not _IMAGING_AVAILABLE:
        out.warnings.append("Reading menus from files isn't set up on this server. "
                            "Type or paste the meals instead.")
        return out
    if not ocr_available():
        out.warnings.append("Reading menus from files isn't set up on this server (Tesseract is missing). "
                            "Type or paste the meals instead.")
        return out
    for page in _pages(data, content_type):
        page = _upright(page)
        rgb = np.asarray(page)
        grey = np.asarray(page.convert("L"))
        dark = grey < 170
        rows = _lines(_longest_runs(dark), 0.5)
        cols = _lines(_longest_runs(dark.T), 0.3)
        if len(rows) < 4 or len(cols) < 3:
            continue
        boxes = {(r, c): (cols[c] + 4, rows[r] + 4, cols[c + 1] - 4, rows[r + 1] - 4)
                 for r in range(len(rows) - 1) if rows[r + 1] - rows[r] > 25
                 for c in range(len(cols) - 1)}
        # The title, above the table.
        if rows[0] > 60:
            _title_hints(_tesseract(page.crop((0, max(0, rows[0] - 400), page.width, rows[0]))), out)
        with ThreadPoolExecutor(max_workers=4) as pool:
            texts = dict(zip(boxes, pool.map(lambda b: _read_cell(rgb, grey, b), boxes.values())))
        table_rows = sorted({r for r, _ in boxes})
        header_row, meal_columns = None, {}
        for r in table_rows:
            found = {c: _meal(texts[(r, c)]) for c in range(len(cols) - 1)}
            found = {c: m for c, m in found.items() if m}
            if len(found) >= 2:
                header_row, meal_columns = r, found
                break
        if header_row is None:
            out.warnings.append("Couldn't find the Breakfast / Lunch / Snacks / Dinner header in the table.")
            continue
        # A title inside the table ("E-Mess Menu Effective from 22/09/2026") is one merged cell: read it whole.
        def strip(r0: int, r1: int, psm: int = 6) -> str:
            return _tesseract(Image.fromarray(grey[r0 + 4:r1 - 4, cols[0] + 4:cols[-1] - 4]), psm=psm)

        title = " ".join(strip(rows[r], rows[r + 1]) for r in table_rows if r < header_row)
        if title:
            _title_hints(title, out)
        notes = []
        last_day_row = None
        for r in table_rows:
            if r <= header_row:
                continue
            day = _weekday(texts[(r, 0)])
            if day:
                last_day_row = r
                for c, meal in meal_columns.items():
                    dishes = _clean(texts[(r, c)])
                    if dishes:
                        out.items[(day, meal)] = dishes
            elif _meal(texts[(r, 0)]):
                # "Breakfast | Tea, Milk, ..." under the week: the row's text spans merged cells.
                rest = _clean(_tesseract(Image.fromarray(grey[rows[r] + 4:rows[r + 1] - 4,
                                                               cols[1] + 4:cols[-1] - 4]), psm=7))
                if rest:
                    notes.append(f"{_meal(texts[(r, 0)]).capitalize()} every day: {rest}")
        if not notes and last_day_row is not None and last_day_row + 1 < len(rows) - 1:
            # "Daily Breakfast Items: Tea, Milk, ..." lines in one block under the week, without rules between.
            block = grey[rows[last_day_row + 1] + 4:rows[-1] - 4, cols[0] + 4:cols[-1] - 4]
            for text_line in _tesseract(Image.fromarray(block), psm=6, keep_lines=True):
                head, _, rest = text_line.partition(":")
                meal = _meal(head) if len(head) < 40 else None
                if meal and _clean(rest):
                    notes.append(f"{meal.capitalize()} every day: {_clean(rest)}")
        if not notes and page.height - rows[-1] > 40:
            # "• Daily Breakfast items: Raw Oats, Tea, ..." printed under the table (D Mess), in small type:
            # read it enlarged.
            below = page.crop((cols[0], rows[-1] + 6, cols[-1], min(page.height, rows[-1] + 500))).convert("L")
            below = below.resize((below.width * 2, below.height * 2), Image.LANCZOS)
            for text_line in _tesseract(below, psm=6, keep_lines=True):
                head, _, rest = text_line.partition(":")
                meal = _meal(head) if len(head) < 40 and "daily" in head.lower() else None
                if meal and _clean(rest):
                    notes.append(f"{meal.capitalize()} every day: {_clean(rest)}")
        if notes:
            out.notes = "\n".join(notes)
        if out.items:
            break
    if not out.items:
        out.warnings.append("Couldn't read a weekly table from this file. Type or paste the meals instead.")
    elif len(out.items) < 28:
        out.warnings.append(f"Read {len(out.items)} of 28 meals; fill in the rest.")
    return out
