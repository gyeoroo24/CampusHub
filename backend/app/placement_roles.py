"""Reading "roles and compensation" files: what each company offered, in which season, for how much.

Two shapes come from the placement office, and both import as they are (header found by name, any order,
title rows above it skipped, like the other Placement Hub imports):

  Batch,Company,Position,Overall CTC,...                       (three seasons of offers)
  2023 - 24,Observe ai,NLP,4000000,...
  CompanyName,jobtype,jobtitle,description,Anual overall CTC,Anual base CTC/ Month,skillset
  "Qualcomm","Full Time Placement","Engineer SW","-","Refer below table","INR 18,00,000","Check JD"

Compensation is free text in these files ("₹ 12,00,000", "15.05 lakhs.", "₹1200000-₹1500000",
"2021600 rupees per Annum", "3. 3,635,000", "NA", "Refer below table"). parse_inr turns it into rupees a
year with a few deterministic rules (units: lakh/LPA, crore, K; ranges; "per month"; stray list numbers;
Indian digit grouping), and keeps the original text alongside, so nothing is lost when a value can't be
read. Rules beat a model here: the formats are few and regular, the result must be exact, and every
miss is visible in the original text. No model is used.

Columns we never import: who approached the company and internal comments (people's emails and notes).
"""
import csv
import io
import re
from dataclasses import dataclass

from .placement_sheet import MAX_ROWS, RejectedRow, SheetError, _delimiter, _squash, find_header

HEADERS = {
    "company": {"company", "companyname", "company name", "organisation", "organization", "employer"},
    "role": {"position", "jobtitle", "job title", "role", "role title", "profile", "designation", "title"},
    "ctc": {"overall ctc", "anual overall ctc", "annual overall ctc", "ctc", "annual ctc", "compensation",
            "package", "total ctc", "overall compensation", "stipend"},
    "base": {"anual base ctc/ month", "anual base ctc/month", "annual base ctc", "base ctc", "base", "base salary",
             "fixed", "fixed ctc"},
    "year": {"batch", "year", "season", "placement year", "placement season"},
    "job_type": {"jobtype", "job type", "type", "offer type"},
    "description": {"description", "job description", "jd", "details"},
    "skills": {"skillset", "skills", "skill set", "required skills", "eligibility"},
}
REQUIRED = ("company", "role")
JOB_TYPES = {"full time": "full_time", "full-time": "full_time", "fte": "full_time", "placement": "full_time",
             "intern": "internship", "summer": "internship", "ppo": "ppo"}
# Cells that only point elsewhere or say nothing.
_PLACEHOLDER = re.compile(r"^(-+|na|n/a|nil|none|\.+|tbd|tba|refer.*|check.*|see.*|jd attached.*|as per.*|"
                          r"please refer.*|will be.*|not disclosed|confidential)$", re.IGNORECASE)
MIN_INR, MAX_INR = 50_000, 50_000_000   # a year's pay outside this is a misread, not a salary


@dataclass(frozen=True)
class RoleRow:
    line: int
    company: str
    role: str
    placement_year: int | None
    job_type: str
    ctc_text: str | None
    ctc_min: int | None
    ctc_max: int | None
    base_text: str | None
    base_annual: int | None
    description: str | None
    skills: str | None


def _clean_text(value: str) -> str | None:
    value = value.strip()
    return None if not value or _PLACEHOLDER.match(value.rstrip(".")) else value


def parse_inr(text: str | None, monthly_hint: bool = False) -> tuple[int, int] | None:
    """(low, high) rupees a year, or None when the text has no readable amount."""
    if not text:
        return None
    t = text.lower().replace("₹", " ").replace("inr", " ").replace("rs.", " ").replace("rupees", " ")
    # Other currencies stay as text; "2,389,811 + USD 6000 RSU" keeps its rupee part.
    t = re.split(r"\$|\busd\b|€|\beur\b", t)[0]
    monthly = bool(re.search(r"per\s*month|/\s*month|\bp\.?\s*m\b|monthly|/\s*mo\b", t))
    unit = 1
    if re.search(r"(\d|\b)\s*cr(ore)?s?\b", t):
        unit = 10_000_000
    elif re.search(r"(\d|\b)\s*(lakhs?|lacs?|lpa|l)\b", t):
        unit = 100_000
    elif re.search(r"\d\s*k\b", t):
        unit = 1_000
    # "3. 3,635,000": a list number in front of the amount.
    t = re.sub(r"^\s*\d{1,2}\.\s+(?=\d)", "", t)
    numbers = [float(n.replace(",", "")) for n in re.findall(r"\d[\d,]*(?:\.\d+)?", t)]
    # "11,00,000 LPA": already in rupees, the unit is just a habit.
    numbers = [n * unit if n * unit <= MAX_INR else n for n in numbers if n > 0]
    if not numbers:
        return None
    if monthly or (monthly_hint and max(numbers) < 300_000):
        numbers = [n * 12 for n in numbers]
    numbers = [n for n in numbers if MIN_INR <= n <= MAX_INR]
    if not numbers:
        return None
    low, high = min(numbers[:2]), max(numbers[:2])
    return round(low), round(high)


def _year(value: str, default: int | None) -> int | None:
    """"2023 - 24" -> 2024 (a season is named by the year it ends), "2025" -> 2025."""
    years = re.findall(r"\d{2,4}", value)
    if not years:
        return default
    last = years[-1]
    year = int(last) + (2000 if len(last) == 2 else 0)
    return year if 2000 <= year <= 2100 else default


def _job_type(value: str) -> str:
    v = value.lower()
    for key, kind in JOB_TYPES.items():
        if key in v:
            return kind
    return "full_time" if not v.strip() else "other"


def parse_roles(text: str, default_year: int | None = None) -> tuple[list[RoleRow], list[RejectedRow]]:
    lines = text.lstrip("﻿").splitlines()
    if not any(line.strip() for line in lines):
        raise SheetError("The file is empty. It needs a header row and at least one role.")
    found = find_header(lines, HEADERS, REQUIRED)
    if found is None:
        raise SheetError("Couldn't find the header row. It needs Company and Position (or Job title) columns.")
    first, columns, header = found
    reader = csv.reader(io.StringIO("\n".join(lines[first:])), delimiter=_delimiter(lines[first]))
    next(reader)
    end = reader.line_num   # the header may span lines
    monthly_base = "month" in (header[columns["base"]] if "base" in columns else "")
    accepted: list[RoleRow] = []
    rejected: list[RejectedRow] = []
    seen: dict[tuple, int] = {}   # key -> index in accepted
    # Line numbers: the csv reader may span lines for quoted cells, so count from its own position.
    for cells in reader:
        line, end = first + end + 1, reader.line_num   # where the row starts, even if a cell spans lines
        if not any(c.strip() for c in cells):
            continue
        if len(accepted) + len(rejected) >= MAX_ROWS:
            raise SheetError(f"A file can have at most {MAX_ROWS} roles. Split it into smaller imports.")

        def cell(name: str, squash: bool = True) -> str:
            i = columns.get(name)
            if i is None or i >= len(cells):
                return ""
            return _squash(cells[i]) if squash else cells[i].strip()

        company, role = cell("company"), cell("role")
        year = _year(cell("year"), default_year)
        reason = None
        if not company:
            reason = "Company is empty."
        elif not role:
            reason = "Position is empty."
        elif len(company) > 120 or len(role) > 200:
            reason = "Company or position is too long."
        elif year is None:
            reason = "No season: add a Batch/Year column, or pick the season when importing."
        if reason:
            rejected.append(RejectedRow(line, reason))
            continue
        job_type = _job_type(cell("job_type"))
        key = (company.lower(), role.lower(), year, job_type)
        ctc_text = _clean_text(cell("ctc"))
        base_text = _clean_text(cell("base"))
        ctc = parse_inr(ctc_text)
        base = parse_inr(base_text, monthly_hint=monthly_base)
        row = RoleRow(
            line=line, company=company, role=role, placement_year=year, job_type=job_type,
            ctc_text=ctc_text[:200] if ctc_text else None, ctc_min=ctc[0] if ctc else None,
            ctc_max=ctc[1] if ctc else None, base_text=base_text[:200] if base_text else None,
            base_annual=base[1] if base else None,
            description=(_clean_text(cell("description", squash=False)) or None),
            skills=(_clean_text(cell("skills", squash=False)) or None))
        if key in seen:
            # The same role posted again (another location or batch of openings): one role, the gaps filled in.
            before = accepted[seen[key]]
            accepted[seen[key]] = RoleRow(**{f: getattr(before, f) if getattr(before, f) is not None else getattr(row, f)
                                             for f in RoleRow.__dataclass_fields__})
            continue
        seen[key] = len(accepted)
        accepted.append(row)
    if not accepted and not rejected:
        raise SheetError("The file has a header but no roles.")
    return accepted, rejected
