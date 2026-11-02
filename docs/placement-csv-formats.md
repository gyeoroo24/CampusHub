# Placement Hub CSV imports: formats and how variations are handled

*3 Nov 2026. Code: `backend/app/placement_sheet.py` (placement sheet) and `backend/app/placement_csv.py`
(companies, placement dates). Tests: `backend/tests/test_placement_hub.py`, `test_seniors_and_mess.py`.*

Placement office files are exported from spreadsheets by different people, so no two look exactly
alike. The importers are built to accept the variations below without anyone editing the file first.
Every row is either saved or rejected with its line number and a reason; good rows are never held
back by bad ones, and importing the same file twice updates instead of duplicating.

## The three imports

| Import | Required columns | Optional columns | One row is |
| --- | --- | --- | --- |
| Placement sheet (Manage → Import placement sheet) | Company, Student email, Role | Slot | one selected student; the season is picked in the dialog |
| Companies (Manage → Add companies → Upload a CSV file) | Name | Industry, Website, About | one company |
| Placement dates (Manage → Add placement dates → Upload a CSV file) | Company | Type, Date, Time (or one date-and-time column), Venue, Details, Mode, Status, Remarks | one PPT, online test, interview or other date |

## Variations handled

### Where the header is
- **Title rows above the header** ("CONGRATULATIONS!!,,,,", a sheet title): the header is the first of the
  first 10 non-blank lines that has every required column. Line numbers in errors still count from the
  top of the file, so they match what the moderator sees in Excel.
- **Byte-order mark** at the start (Excel's "CSV UTF-8"): ignored.
- **Separator**: comma, semicolon or tab (cells copied straight from a spreadsheet), detected from the
  header line. Quoted cells with commas inside ("Postponed, OCCaP will communicate") are kept whole.

### Column names
- **Any order, any case, extra spaces**: columns are found by name, not position.
- **Synonyms**: e.g. Email / Email Id / Student email / IISc email; Role / Profile / Designation;
  Company / Company name / Organisation; Time / Timings / Start time; Remarks / Comments.
- **Round prefixes**: placement office sheets name columns after the round: "Test Date",
  "Interview Venue", "PPT Timings". The prefix is dropped to find the column, and it sets the **type of
  every row** that has no Type column: a "Test …" sheet imports as online tests (OA), an "Interview …"
  sheet as interviews, a "PPT …" sheet as pre-placement talks. A Type column always wins.
- **Misspelt extra columns** ("Intervew Day"), and columns we don't use (SNo, POC names, Day): ignored.
- **Missing optional columns**: fine. A schedule row needs at least a date, venue or details.

### Cell values
- **Dates**: 2026-11-20, 20/11/2026, 20-11-2026, 20.11.2026, 20 Nov 2026, Nov 20 2026,
  **Oct 17th 2026**, "OCt 23rd 2026" (any case; st/nd/rd/th dropped). India time unless a timezone is given.
- **Times**: 18:00, 6:00 pm, 6 pm, 18.00, **"02 00 PM"**, and ranges **"02 00 PM - 03 00 PM"** or
  "10:00-11:30" (the start time is used).
- **No time at all** (the interview schedule): the date is saved and shown as **"Time TBA"**, not as a
  made-up 9:00 am. A moderator editing the date to set a time makes it exact.
- **"NA", "N/A", "-", "nil"** in Venue or other cells: treated as empty. "TBD" is kept (it's information).
- **"Accenture [Mock Assessment]"**: the company is Accenture; "Mock Assessment" goes into the details,
  so it doesn't create a second company.
- **Mode, Status, Remarks**: joined into the details ("Mode: Online · Status: Confirmed · Postponed").
- **Emails (placement sheet)**: any address is accepted (rev 19). Personal ones count in the hiring
  numbers; only IISc addresses are listed under "Talk to seniors".
- **Company names** are matched ignoring case and spacing ("google" = "Google"), and new ones are
  created and listed in the result.

### After the import
The result says how many rows were added, updated and rejected, **which types they were saved as**
("Saved as Interview (7)"), and how many dates have already passed. Past dates don't appear under
Upcoming on the Schedule tab; switch it to **Past**.

## Not handled (on purpose), and what to do

| Situation | Why not | What to do |
| --- | --- | --- |
| Two different spellings of one company ("Atlascopco" vs "Atlas Copco") | Guessing merges different companies | Fix the spelling in the file, or edit the company afterwards |
| Excel `.xlsx` files | CSV keeps the importer small and dependency-free | Save as CSV UTF-8, or copy the cells and paste them |
| Several rounds of one company in one row | Ambiguous | One row per date |
| Dates like "next Monday" or "17/10" without a year | Ambiguous | Write the full date |
| A header row more than 10 lines down | Very unlikely; keeps detection fast | Delete the title lines |

## Adding a new variation
1. Add the column name to the alias sets (`HEADERS`, `SCHEDULE_HEADERS`, `COMPANY_HEADERS`), a round
   prefix to `_ROUND_PREFIXES`, or a date/time format to `_DATE_FORMATS` / `_TIME_FORMATS`.
2. Add a row in that style to a test, with the expected result.
3. Keep rejections explicit: a row that can't be read should say why, never be guessed.
