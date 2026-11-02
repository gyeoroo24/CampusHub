"""Reading a placement sheet for the FR-17 bulk import.

Moderators paste the rows from their spreadsheet (copying cells gives tab-separated text) or a
CSV export. The first non-blank line is the header; columns are found by name, in any order:

  Slot | Company | Student email | Role
  Slot 2 | Walmart | chandus@iisc.ac.in | Software Engineer

Every other non-blank line is one selected student. A row is either accepted or rejected with
its line number and a reason, never silently dropped (FR-17 acceptance criterion).
"""
import csv
import io
import re
from dataclasses import dataclass

MAX_ROWS = 5000
# Any address: students with a personal email count towards the hiring numbers too (only IISc
# addresses are offered as seniors to contact).
_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# Accepted header names (lower case, spaces squashed) for each column.
HEADERS = {
    "slot": {"slot", "slot no", "slot number"},
    "company": {"company", "company name", "organisation", "organization", "employer"},
    "email": {"student email", "email", "email id", "e-mail", "mail", "iisc email", "student email id"},
    "role": {"role", "role title", "profile", "designation", "position", "job role"},
}
REQUIRED = ("company", "email", "role")


class SheetError(ValueError):
    """The sheet as a whole can't be read (no header, missing columns, too many rows)."""


@dataclass(frozen=True)
class SheetRow:
    line: int
    slot: str | None
    company: str
    email: str
    role: str


@dataclass(frozen=True)
class RejectedRow:
    line: int
    reason: str


def _squash(value: str) -> str:
    return " ".join(value.split())


def _delimiter(header_line: str) -> str:
    if "\t" in header_line:
        return "\t"
    return ";" if header_line.count(";") > header_line.count(",") else ","


HEADER_SEARCH_LINES = 10


def match_columns(header: list[str], headers: dict[str, set[str]]) -> dict[str, int]:
    columns: dict[str, int] = {}
    for name, aliases in headers.items():
        for i, h in enumerate(header):
            if h in aliases:
                columns[name] = i
                break
    return columns


def find_header(lines: list[str], headers: dict[str, set[str]], required: tuple[str, ...],
                normalize=lambda h: h) -> tuple[int, dict[str, int], list[str]] | None:
    """The header row: the first of the opening non-blank lines that has every required column.
    Spreadsheet exports often start with a title row ("CONGRATULATIONS!!,,,") above it.
    Returns (line index, column index by name, header cells), or None if none of them fits."""
    candidates = [i for i, line in enumerate(lines) if line.strip()][:HEADER_SEARCH_LINES]
    for i in candidates:
        cells = next(csv.reader([lines[i]], delimiter=_delimiter(lines[i])), [])
        header = [normalize(_squash(h).lower()) for h in cells]
        columns = match_columns(header, headers)
        if all(name in columns for name in required):
            return i, columns, header
    return None


def parse_sheet(text: str) -> tuple[list[SheetRow], list[RejectedRow]]:
    """Accepted rows and rejected rows (with spreadsheet line numbers; the first line is line 1)."""
    lines = text.lstrip("﻿").splitlines()
    first = next((i for i, line in enumerate(lines) if line.strip()), None)
    if first is None:
        raise SheetError("The sheet is empty. Paste the header row and at least one student.")
    found = find_header(lines, HEADERS, REQUIRED)
    if found:
        first, columns, _ = found
    else:
        header = [_squash(h).lower() for h in next(csv.reader([lines[first]], delimiter=_delimiter(lines[first])))]
        columns = match_columns(header, HEADERS)
    reader = csv.reader(io.StringIO("\n".join(lines[first:])), delimiter=_delimiter(lines[first]))
    next(reader)
    missing = [name for name in REQUIRED if name not in columns]
    if missing:
        raise SheetError("The header row needs these columns: Company, Student email and Role (Slot is optional). "
                         f"Missing: {', '.join(m.capitalize() for m in missing)}.")

    accepted: list[SheetRow] = []
    rejected: list[RejectedRow] = []
    seen: dict[str, int] = {}
    for offset, cells in enumerate(reader):
        line = first + 2 + offset
        if not any(c.strip() for c in cells):
            continue
        if len(accepted) + len(rejected) >= MAX_ROWS:
            raise SheetError(f"A sheet can have at most {MAX_ROWS} students. Split it into smaller imports.")

        def cell(name: str) -> str:
            i = columns.get(name)
            return _squash(cells[i]) if i is not None and i < len(cells) else ""

        company, email, role, slot = cell("company"), cell("email").lower(), cell("role"), cell("slot")
        reason = None
        if not company:
            reason = "Company is empty."
        elif len(company) > 120:
            reason = "Company name is longer than 120 characters."
        elif not email:
            reason = "Student email is empty."
        elif not _EMAIL.match(email):
            reason = f"“{email}” isn't an email address."
        elif not role:
            reason = "Role is empty."
        elif len(role) > 200:
            reason = "Role is longer than 200 characters."
        elif len(slot) > 40:
            reason = "Slot is longer than 40 characters."
        elif email in seen:
            reason = f"Same student email as line {seen[email]}; a student appears once per placement year."
        if reason:
            rejected.append(RejectedRow(line, reason))
            continue
        seen[email] = line
        accepted.append(SheetRow(line, slot or None, company, email, role))
    if not accepted and not rejected:
        raise SheetError("The sheet has a header but no students.")
    return accepted, rejected
