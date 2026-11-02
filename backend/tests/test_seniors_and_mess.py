"""Rev 18: seniors to contact on company pages, mess menus with meal alerts, and the placement-office file
formats (a title row above the header; "Test Date" / "Test Timings" schedule columns)."""
import asyncio
from datetime import date, datetime, timedelta

import asyncpg
import pytest

from app import mess_alerts
from app.db import _init_connection
from app.mess_alerts import IST, send_due_meal_alerts

from .conftest import ADMIN, API, ASHA, DB_URL, KIRAN, MEERA, RAVI, grant, make_admin, sign_in, sql, upload


@pytest.fixture
def people(client):
    """Admin; Ravi moderates Placement Hub; Meera moderates Events; Asha and Kiran are students."""
    make_admin(client, ADMIN)
    for h in (RAVI, ASHA, MEERA, KIRAN):
        sign_in(client, h)
    assert grant(client, ADMIN, "ravi@iisc.ac.in", "placement_hub").status_code == 201
    assert grant(client, ADMIN, "meera@iisc.ac.in", "events").status_code == 201


# ---------------------------------------------------------------- placement office files
def test_sheet_with_a_title_row_and_an_office_schedule(client, people):
    this_year = datetime.now(IST).year
    sheet = ("﻿CONGRATULATIONS!!,,,,\n"
             "Slot,Company,Email Id,Profile,Selection Status\n"
             "PPO,Applied materials,asha@iisc.ac.in,Process Engineer,Blocked for Selected Company\n"
             "Slot 1,Applied materials,someone@gmail.com,Engineer,Blocked\n"
             "Slot 1,Applied materials,nobody,Engineer,Blocked\n")
    r = client.post(f"{API}/placement/imports", headers=RAVI, json={"placement_year": this_year, "sheet": sheet})
    assert r.status_code == 201, r.text
    body = r.json()
    assert (body["rows_created"], body["rows_rejected"]) == (2, 1)   # a Gmail address counts too
    assert body["rejected_rows"][0]["line"] == 5          # lines count from the top of the file

    schedule = ("SNo,OCCaP P POC,Company,Test Mode,Test Venue,Test Date,Test Day,Test Timings,Test Schedule Status,Remarks\n"
                "1,Komali,Accenture [Mock Assessment],Online,NA,Oct 17th 2030,Saturday,02 00 PM - 03 00 PM,Confirmed,"
                "\"Postponed, OCCaP Will communicate\"\n"
                "2,Komali,HPE,In Person,OCCaP Office,Oct 19th 2030,Monday,07 30 AM - 08 45 AM,Confirmed,\n")
    r = client.post(f"{API}/placement/schedule/import", headers=RAVI, json={"csv": schedule})
    assert r.status_code == 201, r.text
    assert (r.json()["rows_created"], r.json()["rows_rejected"]) == (2, 0)
    rows = {p["company_name"]: p for p in client.get(f"{API}/placement/ppts").json()["items"]}
    accenture = rows["Accenture"]
    assert accenture["kind"] == "oa" and accenture["venue"] is None       # "Test ..." columns: online tests
    assert accenture["details"] == "Mock Assessment · Mode: Online · Status: Confirmed · Postponed, OCCaP Will communicate"
    when = datetime.fromisoformat(accenture["scheduled_at"]).astimezone(IST)
    assert (when.date(), when.hour, when.minute) == (date(2030, 10, 17), 14, 0)
    assert rows["HPE"]["venue"] == "OCCaP Office"


# ---------------------------------------------------------------- seniors
def test_seniors_to_contact(client, people):
    this_year = datetime.now(IST).year
    sheet = ("Slot,Company,Email Id,Profile\n"
             "PPO,Nvidia,asha@iisc.ac.in,SDE\n"
             "Slot 2,Nvidia,old.student@iisc.ac.in,Hardware Engineer\n"
             "Slot 2,Nvidia,personal@gmail.com,Hardware Engineer\n")
    client.post(f"{API}/placement/imports", headers=RAVI, json={"placement_year": this_year, "sheet": sheet})
    client.post(f"{API}/placement/imports", headers=RAVI, json={
        "placement_year": this_year - 3, "sheet": "Company,Email,Role\nNvidia,ancient@iisc.ac.in,SDE\n"})
    sql("UPDATE users SET phone = '+919876543210' WHERE email = 'asha@iisc.ac.in'")
    nvidia = client.get(f"{API}/companies", params={"q": "nvidia"}).json()["items"][0]["id"]

    assert client.get(f"{API}/companies/{nvidia}/seniors").status_code == 401        # guests see nobody
    added = client.post(f"{API}/companies/{nvidia}/seniors", headers=RAVI, json={
        "name": "Dev Rao", "email": "Dev@Gmail.com", "role_title": "Research Scientist",
        "placement_year": this_year - 1, "offer_type": "off_campus", "note": "Off-campus via referral"})
    assert added.status_code == 201, added.text
    assert client.post(f"{API}/companies/{nvidia}/seniors", headers=KIRAN, json={
        "name": "X", "email": "x@y.com", "placement_year": this_year}).status_code == 403

    seniors = client.get(f"{API}/companies/{nvidia}/seniors", headers=KIRAN).json()
    by_email = {s["email"]: s for s in seniors}
    # Last two seasons only; sheet students with a personal email count in the numbers but aren't listed.
    assert set(by_email) == {"asha@iisc.ac.in", "old.student@iisc.ac.in", "dev@gmail.com"}
    asha = by_email["asha@iisc.ac.in"]
    assert (asha["name"], asha["phone"], asha["offer_type"], asha["source"]) == ("Asha", "+919876543210", "ppo",
                                                                                 "placement_sheet")
    assert asha["user_id"] is not None                     # has an account, so the app offers chat
    assert by_email["old.student@iisc.ac.in"]["user_id"] is None
    assert by_email["old.student@iisc.ac.in"]["name"] == "old.student"
    assert by_email["dev@gmail.com"]["note"] == "Off-campus via referral"

    # Moderators edit the people they added, and hide sheet students.
    r = client.patch(f"{API}/seniors/{added.json()['id']}", headers=RAVI, json={"phone": "9123456789"})
    assert r.status_code == 200 and r.json()["phone"] == "9123456789"
    sheet_row = by_email["old.student@iisc.ac.in"]["id"]
    assert client.put(f"{API}/placement/records/{sheet_row}/contact-hidden", headers=KIRAN,
                      json={"hidden": True}).status_code == 403
    assert client.put(f"{API}/placement/records/{sheet_row}/contact-hidden", headers=RAVI,
                      json={"hidden": True}).status_code == 204
    assert "old.student@iisc.ac.in" not in {s["email"] for s in client.get(
        f"{API}/companies/{nvidia}/seniors", headers=KIRAN).json()}
    moderator_view = client.get(f"{API}/companies/{nvidia}/seniors", headers=RAVI).json()
    assert [s["hidden"] for s in moderator_view if s["email"] == "old.student@iisc.ac.in"] == [True]
    assert client.delete(f"{API}/seniors/{added.json()['id']}", headers=RAVI).status_code == 204


# ---------------------------------------------------------------- mess menus
def _grid(day_items: dict[int, str]) -> list[dict]:
    return [{"weekday": d, "meal": meal, "items": f"{text} {meal}"}
            for d, text in day_items.items() for meal in ("breakfast", "lunch", "snacks", "dinner")]


def _run_alerts(now: datetime):
    async def go():
        conn = await asyncpg.connect(DB_URL)
        await _init_connection(conn)
        try:
            return await send_due_meal_alerts(conn, now)
        finally:
            await conn.close()
    return asyncio.run(go())


def test_mess_menu_and_meal_alerts(client, people, s3, monkeypatch):
    async def no_push(*_):
        return None
    monkeypatch.setattr(mess_alerts, "deliver_push", no_push)

    assert client.post(f"{API}/messes", headers=ASHA, json={"name": "C Mess"}).status_code == 403
    r = client.post(f"{API}/messes", headers=MEERA, json={"name": " C  Mess ", "meal_times": {
        "breakfast": "07:30", "lunch": "12:30", "snacks": "16:45", "dinner": "19:30"}})
    assert r.status_code == 201, r.text
    mess = r.json()
    assert mess["name"] == "C Mess" and mess["today"] == []
    assert client.post(f"{API}/messes", headers=MEERA, json={"name": "c mess"}).status_code == 409

    today = datetime.now(IST).date()
    pdf = upload(client, s3, MEERA, "mess_menu", content=b"%PDF-1.7 menu", content_type="application/pdf")
    body = {"valid_from": (today - timedelta(days=3)).isoformat(), "valid_to": (today + timedelta(days=25)).isoformat(),
            "file_s3_key": pdf, "items": _grid({d: f"Day{d}" for d in range(1, 8)})}
    r = client.post(f"{API}/messes/{mess['id']}/menus", headers=MEERA, json=body)
    assert r.status_code == 201, r.text
    menu = r.json()
    assert menu["file_type"] == "pdf" and menu["file_url"] and len(menu["items"]) == 28
    overlap = body | {"valid_from": (today + timedelta(days=20)).isoformat(), "file_s3_key": None,
                      "valid_to": (today + timedelta(days=40)).isoformat()}
    assert client.post(f"{API}/messes/{mess['id']}/menus", headers=MEERA, json=overlap).status_code == 409

    listed = client.get(f"{API}/messes").json()
    assert listed["can_manage"] is False
    c_mess = listed["messes"][0]
    assert [m["meal"] for m in c_mess["today"]] == ["breakfast", "lunch", "snacks", "dinner"]
    assert c_mess["today"][1]["items"] == f"Day{today.isoweekday()} lunch"
    assert client.get(f"{API}/messes", headers=MEERA).json()["can_manage"] is True

    # Asha wants lunch and dinner alerts; Kiran only breakfast; Ravi doesn't follow.
    r = client.put(f"{API}/messes/{mess['id']}/follow", headers=ASHA, json={"meals": ["dinner", "lunch"]})
    assert r.json()["following_meals"] == ["lunch", "dinner"]
    client.put(f"{API}/messes/{mess['id']}/follow", headers=KIRAN, json={"meals": ["breakfast"]})
    assert client.put(f"{API}/messes/{mess['id']}/follow", json={"meals": ["lunch"]}).status_code == 401

    def at(hour, minute):
        return datetime.combine(today, datetime.min.time().replace(hour=hour, minute=minute), tzinfo=IST)

    assert _run_alerts(at(11, 0)) == []                                   # too early for lunch
    assert _run_alerts(at(12, 10)) == [("C Mess", "lunch", 1)]            # 20 min before lunch
    assert _run_alerts(at(12, 20)) == []                                  # sent once only
    note = client.get(f"{API}/me/notifications", headers=ASHA).json()["items"][0]
    assert note["type"] == "mess_menu"
    assert note["payload"]["message"] == f"C Mess · Lunch at 12:30 pm today: Day{today.isoweekday()} lunch"
    assert _run_alerts(at(17, 30)) == []      # snacks started over 30 minutes ago: too late to alert
    assert not [n for n in client.get(f"{API}/me/notifications", headers=RAVI).json()["items"] if n["type"] == "mess_menu"]

    # Unfollowing stops the alerts; editing the menu replaces its cells.
    client.put(f"{API}/messes/{mess['id']}/follow", headers=ASHA, json={"meals": []})
    assert _run_alerts(at(19, 10)) == [("C Mess", "dinner", 0)]
    r = client.patch(f"{API}/mess-menus/{menu['id']}", headers=MEERA, json={
        "items": [{"weekday": 1, "meal": "lunch", "items": "Biryani"}], "file_s3_key": None})
    assert r.status_code == 200, r.text
    assert r.json()["items"] == [{"weekday": 1, "meal": "lunch", "items": "Biryani"}] and r.json()["file_url"] is None
    assert client.delete(f"{API}/mess-menus/{menu['id']}", headers=ASHA).status_code == 403
    assert client.delete(f"{API}/mess-menus/{menu['id']}", headers=MEERA).status_code == 204


def test_a_menu_can_be_just_the_file_and_still_alerts(client, people, s3, monkeypatch):
    async def no_push(*_):
        return None
    monkeypatch.setattr(mess_alerts, "deliver_push", no_push)
    mess = client.post(f"{API}/messes", headers=MEERA, json={"name": "A Mess"}).json()
    today = datetime.now(IST).date()
    dates = {"valid_from": today.isoformat(), "valid_to": (today + timedelta(days=10)).isoformat()}
    r = client.post(f"{API}/messes/{mess['id']}/menus", headers=MEERA, json=dates)
    assert r.status_code == 422                                     # neither a file nor any meal
    photo = upload(client, s3, MEERA, "mess_menu")
    r = client.post(f"{API}/messes/{mess['id']}/menus", headers=MEERA, json=dates | {"file_s3_key": photo})
    assert r.status_code == 201, r.text
    assert r.json()["items"] == [] and r.json()["file_type"] == "image"
    client.put(f"{API}/messes/{mess['id']}/follow", headers=ASHA, json={"meals": ["dinner"]})
    dinner = datetime.combine(today, datetime.min.time().replace(hour=19, minute=10), tzinfo=IST)
    assert _run_alerts(dinner) == [("A Mess", "dinner", 1)]
    note = client.get(f"{API}/me/notifications", headers=ASHA).json()["items"][0]
    assert note["payload"]["message"] == "A Mess · Dinner at 7:30 pm today. Tap to see the menu."


# ---------------------------------------------------------------- rev 20: menu files and event cards
MENU_PDF = __import__("pathlib").Path(__file__).resolve().parents[3] / "C mess menu.pdf"


@pytest.mark.skipif(not (__import__("shutil").which("tesseract") and MENU_PDF.exists()),
                    reason="needs Tesseract and the sample C Mess menu")
def test_reading_the_meals_from_a_menu_pdf(client, people, s3):
    key = upload(client, s3, MEERA, "mess_menu", content=MENU_PDF.read_bytes(), content_type="application/pdf")
    assert client.post(f"{API}/mess-menus/extract", headers=ASHA, json={"file_s3_key": key}).status_code == 403
    r = client.post(f"{API}/mess-menus/extract", headers=MEERA, json={"file_s3_key": key})
    assert r.status_code == 200, r.text
    found = r.json()
    assert found["mess_name"] == "C Mess"
    cells = {(i["weekday"], i["meal"]): i["items"] for i in found["items"]}
    assert len(cells) == 28
    assert "Pongal" in cells[(3, "breakfast")] and "Bhatura" in cells[(7, "lunch")]
    assert "Breakfast every day: Tea, Milk" in found["notes"]


def test_a_mess_menu_keeps_its_event_card(client, people, s3):
    today = datetime.now(IST).date()
    body = {"mess_name": "D Mess", "valid_from": today.isoformat(), "valid_to": (today + timedelta(days=20)).isoformat(),
            "items": [{"weekday": d, "meal": "lunch", "items": "Chapati, Dal, Rice, Curd"} for d in range(1, 8)]
            + [{"weekday": 1, "meal": "dinner", "items": "Biryani, Raita"}]}
    assert client.post(f"{API}/mess-menus", headers=ASHA, json=body).status_code == 403
    r = client.post(f"{API}/mess-menus", headers=MEERA, json=body)                # adds the mess too
    assert r.status_code == 201, r.text
    mess_id = r.json()["mess_id"]
    events = [e for e in client.get(f"{API}/events").json()["items"] if e["mess_id"] == mess_id]
    assert len(events) == 1
    card = events[0]
    assert card["title"] == "D Mess: what's on the menu" and [t["name"] for t in card["tags"]] == ["Food/Mess"]
    assert "Lunch 12:30 pm" in card["description"] and "Lunch: Chapati, Dal, Rice, Curd" in card["description"]
    assert card["can_edit"] is False                                              # edited through the menu

    # A new menu for the same mess (by name, any case) updates the same card.
    later = {"mess_name": "d mess", "valid_from": (today + timedelta(days=21)).isoformat(),
             "valid_to": (today + timedelta(days=50)).isoformat(),
             "items": [{"weekday": 1, "meal": "lunch", "items": "Pulao"}]}
    assert client.post(f"{API}/mess-menus", headers=MEERA, json=later).status_code == 201
    cards = [e for e in client.get(f"{API}/events").json()["items"] if e["mess_id"] == mess_id]
    assert len(cards) == 1 and cards[0]["end_time"].startswith((today + timedelta(days=50)).isoformat())
    assert len(client.get(f"{API}/messes").json()["messes"]) == 1

    # Removing the mess removes its card.
    assert client.delete(f"{API}/messes/{mess_id}", headers=MEERA).status_code == 204
    assert not [e for e in client.get(f"{API}/events").json()["items"] if e["mess_id"] == mess_id]


def test_interview_schedule_without_times(client, people):
    sheet = ("SNo,OCCaP P POC,Company,Interview Mode,Interview Venue,Interview Date,Intervew Day,Remarks\n"
             "1,Komali,HPE,In Person,OCCaP Office,Oct 19th 2030,Monday,\n"
             "2,Komali,Chevron,In Person,TBD,OCt 23rd 2030,Friday,\n")
    r = client.post(f"{API}/placement/schedule/import", headers=RAVI, json={"csv": sheet})
    assert r.status_code == 201, r.text
    assert r.json()["kinds"] == {"interview": 2} and r.json()["past_rows"] == 0
    dates = client.get(f"{API}/placement/ppts", params={"kind": "interview"}).json()["items"]
    assert [(d["company_name"], d["time_tbd"]) for d in dates] == [("HPE", True), ("Chevron", True)]
    # A moderator setting the time makes it exact.
    r = client.patch(f"{API}/ppts/{dates[0]['id']}", headers=RAVI, json={"scheduled_at": "2030-10-19T10:30:00+05:30"})
    assert r.json()["time_tbd"] is False
