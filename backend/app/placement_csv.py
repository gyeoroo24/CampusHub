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

from .placement_sheet import MAX_ROWS, RejectedRow, SheetError, _delimiter, _squash, find_header

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
    "date": {"date"},
    "time": {"time", "start time", "starts", "timings", "timing", "slot time"},
    "when": {"date and time", "datetime", "date time", "when", "scheduled at"},
    "venue": {"venue", "place", "where", "location", "link"},
    "details": {"details", "description", "notes", "info"},
    "mode": {"mode"},
    "status": {"status", "schedule status"},
    "remarks": {"remarks", "remark", "comments", "comment"},
}
# Placement-office sheets name columns after the round: "Test Date", "Interview Venue", "PPT Timings".
# The prefix is dropped to find the column, and it sets the type of every row that has no Type cell.
_ROUND_PREFIXES = {"test": "oa", "oa": "oa", "online test": "oa", "interview": "interview",
                   "ppt": "ppt", "talk": "ppt"}
_EMPTY = {"na", "n/a", "-", "--", "nil", "none"}
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
    time_tbd: bool = False      # a date without a time: stored at 09:00 India time, shown as "time TBA"


def _strip_round(header: str) -> str:
    for prefix in sorted(_ROUND_PREFIXES, key=len, reverse=True):
        if header.startswith(prefix + " ") and len(header) > len(prefix) + 1:
            return header[len(prefix) + 1:]
    return header


def _round_kind(header: list[str]) -> str | None:
    """The type a sheet's column names imply ("Test Date" -> oa), if they all agree."""
    kinds = {kind for h in header for prefix, kind in _ROUND_PREFIXES.items() if h.startswith(prefix + " ")}
    return kinds.pop() if len(kinds) == 1 else None


def _rows(text: str, headers: dict[str, set[str]], required: tuple[str, ...], what: str, normalize=lambda h: h):
    """(column index by name, raw header cells, [(line, cells)]) for every non-blank row after the header."""
    lines = text.lstrip("﻿").splitlines()
    if not any(line.strip() for line in lines):
        raise SheetError(f"The file is empty. It needs a header row and at least one {what}.")
    found = find_header(lines, headers, required, normalize)
    if found is None:
        raise SheetError(f"Couldn't find the header row. It needs a {', '.join(m.capitalize() for m in required)} "
                         "column within the first 10 lines.")
    first, columns, _ = found
    raw_header = [_squash(h).lower() for h in next(csv.reader([lines[first]], delimiter=_delimiter(lines[first])))]
    reader = csv.reader(io.StringIO("\n".join(lines[first:])), delimiter=_delimiter(lines[first]))
    next(reader)
    rows = []
    for offset, cells in enumerate(reader):
        if any(c.strip() for c in cells):
            rows.append((first + 2 + offset, cells))
    if not rows:
        raise SheetError(f"The file has a header but no {what} rows.")
    if len(rows) > MAX_ROWS:
        raise SheetError(f"A file can have at most {MAX_ROWS} rows. Split it into smaller imports.")
    return columns, raw_header, rows


def _cell(columns: dict[str, int], cells: list[str], name: str) -> str:
    i = columns.get(name)
    return _squash(cells[i]) if i is not None and i < len(cells) else ""


def parse_companies(text: str) -> tuple[list[CompanyRow], list[RejectedRow]]:
    columns, _, rows = _rows(text, COMPANY_HEADERS, ("name",), "company")
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


# Where a date with no time goes. 09:00 keeps the day right in every timezone and sorts sensibly.
_NO_TIME = time(9, 0)

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
    # A range ("02 00 PM - 03 00 PM", "10:00-11:30") starts at its first time.
    value = re.split(r"\s+(?:-|–|to)\s+|(?<=\d)-(?=\d)", value.strip(), maxsplit=1, flags=re.IGNORECASE)[0]
    value = re.sub(r"^(\d{1,2})\s+(\d{2})\b", r"\1:\2", value.strip())   # "02 00 PM" -> "02:00 PM"
    value = " ".join(value.upper().split())
    for fmt in _TIME_FORMATS:
        try:
            return datetime.strptime(value, fmt).time()
        except ValueError:
            continue
    return None


def _parse_when(when: str, day: str, at: str) -> datetime | None | str:
    """The moment in IST, None when no date is given, or an error message. A date without a time
    comes back at _NO_TIME (09:00); parse_schedule marks those rows time_tbd."""
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
    t = _NO_TIME
    if at:
        parsed_time = _parse_time(at)
        if parsed_time is None:
            return f"Couldn't read the time “{at}”. Use 18:00 or 6:00 pm."
        t = parsed_time
    return datetime.combine(d, t, tzinfo=IST)


def parse_schedule(text: str) -> tuple[list[ScheduleRow], list[RejectedRow]]:
    columns, header, rows = _rows(text, SCHEDULE_HEADERS, ("company",), "schedule", _strip_round)
    default_kind = _round_kind(header) or "ppt"
    accepted: list[ScheduleRow] = []
    rejected: list[RejectedRow] = []
    for line, cells in rows:
        company = _cell(columns, cells, "company")
        kind_text = _cell(columns, cells, "kind").lower()
        venue = _cell(columns, cells, "venue")
        if venue.lower() in _EMPTY:
            venue = ""
        # "Accenture [Mock Assessment]": the bracketed part describes the round, not the company.
        notes = []
        m = re.fullmatch(r"(.+?)\s*[\[(]([^\])]+)[\])]", company)
        if m:
            company, round_name = m.group(1).strip(), m.group(2).strip()
            notes.append(round_name)
        for name, label in (("mode", "Mode"), ("status", "Status"), ("remarks", None), ("details", None)):
            value = _cell(columns, cells, name)
            if value and value.lower() not in _EMPTY:
                notes.append(f"{label}: {value}" if label else value)
        details = " · ".join(notes)
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
        when_cell = _cell(columns, cells, "when")
        tbd = (isinstance(when, datetime) and not _cell(columns, cells, "time")
               and not re.search(r"\d[:.]\d\d|\d\s*[ap]\.?m|T\d", when_cell, re.IGNORECASE))
        accepted.append(ScheduleRow(line, company, KINDS.get(kind_text, default_kind), when, venue or None, details or None,
                                    time_tbd=tbd))
    return accepted, rejected
