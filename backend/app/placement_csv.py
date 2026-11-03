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
    "shortlist": {"shortlist released", "shortlist", "shortlist status"},
}
# Placement-office sheets name columns after the round: "Test Date", "Interview Venue", "PPT Timings", or
# "Venue of Interview", "Mode of Test". The round is dropped to find the column, and it sets the type of every
# row that has no Type cell. Without one, the file's name decides ("slot 2 interview schedule.csv").
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


def _header_round(header: str) -> tuple[str, str | None]:
    """("venue", "interview") for "Venue of Interview" or "Interview Venue"; a note in brackets
    ("Date [MM/DD/YYYY]") and a trailing "?" are dropped first."""
    header = " ".join(re.sub(r"\[[^\]]*\]|\([^)]*\)|\?", " ", header).split())
    for name in sorted(_ROUND_PREFIXES, key=len, reverse=True):
        if header.startswith(name + " ") and len(header) > len(name) + 1:
            return header[len(name) + 1:], _ROUND_PREFIXES[name]
        if header.endswith(" of " + name) and len(header) > len(name) + 4:
            return header[:-len(name) - 4], _ROUND_PREFIXES[name]
    return header, None


def _strip_round(header: str) -> str:
    return _header_round(header)[0]


def _round_kind(header: list[str]) -> str | None:
    """The type a sheet's column names imply ("Test Date", "Venue of Interview"), if they all agree."""
    kinds = {kind for h in header if (kind := _header_round(h)[1])}
    return kinds.pop() if len(kinds) == 1 else None


def kind_from_file_name(file_name: str | None) -> str | None:
    """"slot 2 interview schedule.csv" -> interview, "Test schedule" -> oa, "PPT dates" -> ppt."""
    words = set(re.findall(r"[a-z]+", (file_name or "").lower()))
    kinds = {kind for word, kind in (("interview", "interview"), ("interviews", "interview"), ("test", "oa"),
                                     ("tests", "oa"), ("oa", "oa"), ("assessment", "oa"), ("ppt", "ppt"),
                                     ("ppts", "ppt"), ("talk", "ppt"), ("talks", "ppt")) if word in words}
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
    reader = csv.reader(io.StringIO("\n".join(lines[first:])), delimiter=_delimiter(lines[first]))
    raw_header = [_squash(h).lower() for h in next(reader)]
    rows = []
    end = reader.line_num   # the header may span lines ("Date⏎[MM/DD/YYYY]")
    for cells in reader:
        line, end = first + end + 1, reader.line_num   # where the row starts, even if a cell spans lines
        if any(c.strip() for c in cells):
            rows.append((line, cells))
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

_DATE_FORMATS = ("%Y-%m-%d", "%d-%m-%Y", "%d/%m/%Y", "%d.%m.%Y", "%d %b %Y", "%d %B %Y", "%b %d %Y", "%B %d %Y",
                 "%d-%b-%y", "%d-%b-%Y", "%d %b %y", "%d/%m/%y")
_MONTH_FIRST = {"%d-%m-%Y": "%m-%d-%Y", "%d/%m/%Y": "%m/%d/%Y", "%d.%m.%Y": "%m.%d.%Y", "%d/%m/%y": "%m/%d/%y"}
_TIME_FORMATS = ("%H:%M", "%H.%M", "%I:%M %p", "%I:%M%p", "%I %p", "%I%p", "%H:%M:%S")


def _parse_date(value: str, month_first: bool = False) -> date | None:
    value = value.replace(",", " ")
    value = re.sub(r"(\d)(st|nd|rd|th)\b", r"\1", value)
    value = " ".join(value.split())
    for fmt in _DATE_FORMATS:
        fmt = _MONTH_FIRST.get(fmt, fmt) if month_first else fmt
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


def _month_first(header: list[str], dates: list[str]) -> bool:
    """Whether numeric dates are month/day ("10/5/2026" = 5 Oct): the header says so ("Date [MM/DD/YYYY]"),
    or a date only reads that way ("9/28/2026"). Otherwise day/month, as written in India."""
    if any(re.search(r"mm\W?dd", h) for h in header):
        return True
    if any(re.search(r"dd\W?mm", h) for h in header):
        return False
    pairs = [(int(m.group(1)), int(m.group(2))) for d in dates if (m := re.match(r"\s*(\d{1,2})[/.-](\d{1,2})[/.-]\d", d))]
    return any(b > 12 for _, b in pairs) and not any(a > 12 for a, _ in pairs)


def _parse_when(when: str, day: str, at: str, month_first: bool = False) -> datetime | None | str:
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
    d = _parse_date(day, month_first)
    if d is None:
        return f"Couldn't read the date “{day}”. Use 2026-11-20 or 20/11/2026."
    t = _NO_TIME
    if at:
        parsed_time = _parse_time(at)
        if parsed_time is None:
            return f"Couldn't read the time “{at}”. Use 18:00 or 6:00 pm."
        t = parsed_time
    return datetime.combine(d, t, tzinfo=IST)


def parse_schedule(text: str, file_name: str | None = None) -> tuple[list[ScheduleRow], list[RejectedRow]]:
    """[file_name] sets the type when neither a Type column nor the column names give it."""
    columns, header, rows = _rows(text, SCHEDULE_HEADERS, ("company",), "schedule", _strip_round)
    default_kind = _round_kind(header) or kind_from_file_name(file_name) or "ppt"
    month_first = _month_first(header, [_cell(columns, cells, "date") or _cell(columns, cells, "when")
                                        for _, cells in rows])
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
        at = _cell(columns, cells, "time")
        if at and _parse_time(at) is None:
            # "No test", "TBD", "2PM (24 hr window)": not a time to put on the calendar. The date stands with
            # the time to be announced, and the text is kept in the details.
            notes.append(f"Time: {at}")
            at = ""
        day = _cell(columns, cells, "date")
        if day and not re.search(r"\d", day):
            # "CANCELLED", "TBD" where the date goes: kept as information, with no date.
            notes.append(f"Date: {day}")
            day = ""
        for name, label in (("mode", "Mode"), ("status", "Status"), ("shortlist", "Shortlist released"),
                            ("remarks", None), ("details", None)):
            value = _cell(columns, cells, name)
            if value and value.lower() not in _EMPTY:
                notes.append(f"{label}: {value}" if label else value)
        details = " · ".join(notes)
        # "10/16/2026 & 10/17/2026": the same round on two days is two dates.
        days = [d for d in re.split(r"\s*(?:&|;|\band\b)\s*", day) if d] or [""]
        when_cell = _cell(columns, cells, "when")
        reason = None
        if not company:
            reason = "Company is empty."
        elif len(company) > 120:
            reason = "Company name is longer than 120 characters."
        elif kind_text and kind_text not in KINDS:
            reason = f"Type “{kind_text}” isn't one of PPT, OA, Interview or Other."
        elif len(venue) > 200:
            reason = "Venue is longer than 200 characters."
        elif len(details) > 5000:
            reason = "Details are longer than 5000 characters."
        whens = [] if reason else [_parse_when(when_cell, d, at, month_first) for d in days]
        if not reason:
            reason = next((w for w in whens if isinstance(w, str)), None)
        if not reason and whens == [None] and not venue and not details:
            reason = "Give at least the date, venue or details."
        if reason:
            rejected.append(RejectedRow(line, reason))
            continue
        tbd = not at and not re.search(r"\d[:.]\d\d|\d\s*[ap]\.?m|T\d", when_cell, re.IGNORECASE)
        for when in whens:
            accepted.append(ScheduleRow(line, company, KINDS.get(kind_text, default_kind), when, venue or None,
                                        details or None, time_tbd=tbd and isinstance(when, datetime)))
    return accepted, rejected
