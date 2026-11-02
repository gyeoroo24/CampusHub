"""Reading a mess menu from the PDF or photo the mess committee shares, to prefill the menu form.

Nothing here is posted: the moderator checks every cell in the app, fixes what was misread, then posts.

  1. Render the page (PDF via pypdfium2, 300 dpi; photos as they are).
  2. Find the table's ruled lines: rows and columns where long runs of dark pixels cross the page.
  3. OCR each cell with Tesseract (the `tesseract` program; Apache-2.0 LSTM OCR, no network, ~0.1 s
     a cell). Coloured text (veg / non-veg colour coding) is easy to lose, so each cell is read three
     ways (grey, and the darkest colour channel at two thresholds) and the cleanest reading kept.
  4. Find the header row (Breakfast / Lunch / Snacks / Dinner) and the weekday in each row, and turn
     the grid into menu cells. Rows below the week whose first cell is a meal ("Breakfast: tea, milk
     ...") become the notes; a title above the table ("C Mess Menu (JUNE 2026)") suggests the mess name
     and month.

Without ruled lines (a photo of a handwritten board, say) or without Tesseract installed, it returns
what it can and says so; the moderator types or pastes the meals instead.
"""
import io
import re
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import date

import numpy as np
from PIL import Image, ImageOps

MEALS = ("breakfast", "lunch", "snacks", "dinner")
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
MONTHS = ("january", "february", "march", "april", "may", "june", "july", "august", "september",
          "october", "november", "december")
MAX_PAGES = 3


@dataclass
class Extracted:
    items: dict[tuple[int, str], str] = field(default_factory=dict)   # (weekday 1-7, meal) -> dishes
    notes: str | None = None
    mess_name: str | None = None
    month: date | None = None          # first day of the month the title names
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


def _tesseract(image: Image.Image, psm: int = 6) -> str:
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        image.save(f.name)
        result = subprocess.run(["tesseract", f.name, "-", "--psm", str(psm)], capture_output=True, text=True,
                                timeout=30)
    return " ".join(result.stdout.split())


def _score(text: str) -> float:
    """How much a reading looks like words: letters in words of 3+ letters, minus stray symbols."""
    tokens = re.findall(r"[A-Za-z]+", text)
    words = [t for t in tokens if len(t) >= 3 and re.search(r"[aeiouyAEIOUY]", t)]
    scraps = [t for t in tokens if len(t) <= 2 and t.lower() not in {"of", "nv", "v", "a", "&"}]
    junk = len(re.findall(r"[^\w\s,./+()&'*-]", text))
    return sum(len(w) for w in words) - 4 * len(scraps) - 3 * junk


def _read_cell(rgb: np.ndarray, grey: np.ndarray, box: tuple[int, int, int, int]) -> str:
    x0, y0, x1, y1 = box
    darkest = rgb[y0:y1, x0:x1].min(axis=2)
    variants = [Image.fromarray(grey[y0:y1, x0:x1])]
    variants += [Image.fromarray(np.where(darkest < t, 0, 255).astype("uint8")) for t in (150, 200)]
    readings = []
    for v in variants:
        v = ImageOps.expand(v.resize((v.width * 2, v.height * 2), Image.LANCZOS), 30, 255)
        readings.append(_tesseract(v))
    return max(readings, key=_score)


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
    m = re.search(r"\b([A-Z0-9][A-Za-z0-9 ]{0,20}?mess)\b", text, re.IGNORECASE)
    if m:
        out.mess_name = " ".join(w.capitalize() if w.lower() == "mess" else w for w in m.group(1).split())
    months = "|".join(MONTHS)
    m = re.search(rf"({months})\W{{0,3}}(\d{{4}})", text, re.IGNORECASE)
    if m:
        out.month = date(int(m.group(2)), MONTHS.index(m.group(1).lower()) + 1, 1)


def extract_menu(data: bytes, content_type: str) -> Extracted:
    out = Extracted()
    if not ocr_available():
        out.warnings.append("Reading menus from files isn't set up on this server (Tesseract is missing). "
                            "Type or paste the meals instead.")
        return out
    for page in _pages(data, content_type):
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
        title = " ".join(texts[(r, c)] for r in table_rows if r < header_row for c in range(len(cols) - 1))
        if title:
            _title_hints(title, out)
        notes = []
        for r in table_rows:
            if r <= header_row:
                continue
            day = _weekday(texts[(r, 0)])
            if day:
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
        if notes:
            out.notes = "\n".join(notes)
        if out.items:
            break
    if not out.items:
        out.warnings.append("Couldn't read a weekly table from this file. Type or paste the meals instead.")
    elif len(out.items) < 28:
        out.warnings.append(f"Read {len(out.items)} of 28 meals; fill in the rest.")
    return out
