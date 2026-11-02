"""Reading the other two CSV files Placement Hub moderators import: the company list and the
placement schedule (pre-placement talks, online tests, interviews). Same rules as the placement
sheet (placement_sheet.py): a header row whose columns are found by name in any order, CSV or
tab-separated, and every other row is accepted or rejected with its line number and a reason.

  Companies:  Name | Industry | Website | About
  Schedule:   Company | Type | Date | Time | Venue | Details
              Google  | OA   | 2026-11-20 | 18:00 | Online (HackerRank) | Coding test, 90 min

Times without a timezone are Indian Standard Time.
"""
import csv
import io
import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone

from .placement_sheet import MAX_ROWS, RejectedRow, SheetError, _delimiter, _squash

IST = timezone(timedelta(hours=5, minutes=30), "IST")

COMPANY_HEADERS = {
    "name": {"name", "company", "company name", "organisation", "organization"},
    "industry": {"industry", "sector", "domain"},
    "website": {"website", "careers page", "careers", "url", "link"},
    "description": {"about", "description", "about the company", "details"},
}
SCHEDULE_HEADERS = {
    "company": {"company", "company name", "organisation", "organization"},
    "kind": {"type", "kind", "event", "round", "stage"},
    "date": {"date", "day"},
    "time": {"time", "start time", "starts"},
    "when": {"date and time", "datetime", "date time", "when", "scheduled at"},
    "venue": {"venue", "place", "where", "location", "link"},
    "details": {"details", "description", "notes", "info"},
}
KINDS = {
    "ppt": "ppt", "pre-placement talk": "ppt", "pre placement talk": "ppt", "talk": "ppt",
    "oa": "oa", "online test": "oa", "online assessment": "oa", "test": "oa", "coding test": "oa",
    "interview": "interview", "interviews": "interview",
    "other": "other",
}


@dataclass(frozen=True)
class CompanyRow:
    line: int
    name: str
    industry: str | None
    website: str | None
    description: str | None


@dataclass(frozen=True)
class ScheduleRow:
    line: int
    company: str
    kind: str
    scheduled_at: datetime | None
    venue: str | None
    details: str | None


def _rows(text: str, headers: dict[str, set[str]], required: tuple[str, ...], what: str):
    """(column index by name, [(line, cells)]) for every non-blank row after the header."""
    lines = text.lstrip("﻿").splitlines()
    first = next((i for i, line in enumerate(lines) if line.strip()), None)
    if first is None:
        raise SheetError(f"The file is empty. It needs a header row and at least one {what}.")
    reader = csv.reader(io.StringIO("\n".join(lines[first:])), delimiter=_delimiter(lines[first]))
    header = [_squash(h).lower() for h in next(reader)]
    columns: dict[str, int] = {}
    for name, aliases in headers.items():
        for i, h in enumerate(header):
            if h in aliases:
                columns[name] = i
                break
    missing = [name for name in required if name not in columns]
    if missing:
        raise SheetError(f"The header row needs a {', '.join(m.capitalize() for m in missing)} column.")
    rows = []
    for offset, cells in enumerate(reader):
        if any(c.strip() for c in cells):
            rows.append((first + 2 + offset, cells))
    if not rows:
        raise SheetError(f"The file has a header but no {what} rows.")
    if len(rows) > MAX_ROWS:
        raise SheetError(f"A file can have at most {MAX_ROWS} rows. Split it into smaller imports.")
    return columns, rows


def _cell(columns: dict[str, int], cells: list[str], name: str) -> str:
    i = columns.get(name)
    return _squash(cells[i]) if i is not None and i < len(cells) else ""


def parse_companies(text: str) -> tuple[list[CompanyRow], list[RejectedRow]]:
    columns, rows = _rows(text, COMPANY_HEADERS, ("name",), "company")
    accepted: list[CompanyRow] = []
    rejected: list[RejectedRow] = []
    seen: dict[str, int] = {}
    for line, cells in rows:
        name, industry = _cell(columns, cells, "name"), _cell(columns, cells, "industry")
        website, about = _cell(columns, cells, "website"), _cell(columns, cells, "description")
        reason = None
        if not name:
            reason = "Name is empty."
        elif len(name) > 120:
            reason = "Name is longer than 120 characters."
        elif len(industry) > 80:
            reason = "Industry is longer than 80 characters."
        elif website and not website.lower().startswith(("https://", "http://")):
            reason = "Website must start with https://"
        elif len(about) > 5000:
            reason = "About is longer than 5000 characters."
        elif name.lower() in seen:
            reason = f"Same company as line {seen[name.lower()]}."
        if reason:
            rejected.append(RejectedRow(line, reason))
            continue
        seen[name.lower()] = line
        accepted.append(CompanyRow(line, name, industry or None, website or None, about or None))
    return accepted, rejected


_DATE_FORMATS = ("%Y-%m-%d", "%d-%m-%Y", "%d/%m/%Y", "%d.%m.%Y", "%d %b %Y", "%d %B %Y", "%b %d %Y", "%B %d %Y")
_TIME_FORMATS = ("%H:%M", "%H.%M", "%I:%M %p", "%I:%M%p", "%I %p", "%I%p", "%H:%M:%S")


def _parse_date(value: str) -> date | None:
    value = value.replace(",", " ")
    value = re.sub(r"(\d)(st|nd|rd|th)\b", r"\1", value)
    value = " ".join(value.split())
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    return None


def _parse_time(value: str) -> time | None:
    value = " ".join(value.upper().split())
    for fmt in _TIME_FORMATS:
        try:
            return datetime.strptime(value, fmt).time()
        except ValueError:
            continue
    return None


def _parse_when(when: str, day: str, at: str) -> datetime | None | str:
    """The moment in IST, None when no date is given, or an error message."""
    if when:
        try:
            parsed = datetime.fromisoformat(when.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=IST)
        except ValueError:
            pass
        # "20/11/2026 6:00 pm", "20 Nov 2026, 18:00": the time is at the end.
        m = re.search(r"[\s,T]+(\d{1,2}([:.]\d{2})?(:\d{2})?\s*([ap]\.?m\.?)?)$", when, re.IGNORECASE)
        if m and (m.group(2) or m.group(4)):
            day, at = when[:m.start()], at or m.group(1).replace(".m.", "m").replace(".m", "m")
        else:
            day = when
    if not day:
        return "Time is given without a date." if at else None
    d = _parse_date(day)
    if d is None:
        return f"Couldn't read the date “{day}”. Use 2026-11-20 or 20/11/2026."
    t = time(9, 0)
    if at:
        parsed_time = _parse_time(at)
        if parsed_time is None:
            return f"Couldn't read the time “{at}”. Use 18:00 or 6:00 pm."
        t = parsed_time
    return datetime.combine(d, t, tzinfo=IST)


def parse_schedule(text: str) -> tuple[list[ScheduleRow], list[RejectedRow]]:
    columns, rows = _rows(text, SCHEDULE_HEADERS, ("company",), "schedule")
    accepted: list[ScheduleRow] = []
    rejected: list[RejectedRow] = []
    for line, cells in rows:
        company = _cell(columns, cells, "company")
        kind_text = _cell(columns, cells, "kind").lower()
        venue, details = _cell(columns, cells, "venue"), _cell(columns, cells, "details")
        when = _parse_when(_cell(columns, cells, "when"), _cell(columns, cells, "date"), _cell(columns, cells, "time"))
        reason = None
        if not company:
            reason = "Company is empty."
        elif len(company) > 120:
            reason = "Company name is longer than 120 characters."
        elif kind_text and kind_text not in KINDS:
            reason = f"Type “{kind_text}” isn't one of PPT, OA, Interview or Other."
        elif isinstance(when, str):
            reason = when
        elif len(venue) > 200:
            reason = "Venue is longer than 200 characters."
        elif len(details) > 5000:
            reason = "Details are longer than 5000 characters."
        elif when is None and not venue and not details:
            reason = "Give at least the date, venue or details."
        if reason:
            rejected.append(RejectedRow(line, reason))
            continue
        accepted.append(ScheduleRow(line, company, KINDS.get(kind_text, "ppt"), when, venue or None, details or None))
    return accepted, rejected
