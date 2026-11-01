"""Placement Hub (FR-15, FR-16, FR-17): companies, JDs, PPTs, hiring statistics, interview
experiences, the company forum and the placement sheet import."""
from datetime import datetime, timedelta, timezone

import pytest

from app.placement_sheet import SheetError, parse_sheet

from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, grant, make_admin, sign_in, sql, upload


@pytest.fixture
def placement(client):
    """Admin; Ravi moderates Placement Hub; Asha, Meera and Kiran are students."""
    make_admin(client, ADMIN)
    for h in (RAVI, ASHA, MEERA, KIRAN):
        sign_in(client, h)
    assert grant(client, ADMIN, "ravi@iisc.ac.in", "placement_hub").status_code == 201


def _company(client, name="Walmart Global Tech", **fields):
    r = client.post(f"{API}/companies", headers=RAVI, json={"name": name} | fields)
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------- companies, JDs, PPTs (FR-15)
def test_company_page_has_explicit_empty_states(client, placement):
    company = _company(client, industry="Retail technology", website="https://careers.walmart.com")
    page = client.get(f"{API}/companies/{company['id']}").json()      # guest
    assert page["job_descriptions"] == [] and page["ppts"] == []
    assert page["latest_year"] is None and page["total_selected"] == 0
    assert page["viewer_can_manage"] is False
    assert client.get(f"{API}/companies/{company['id']}", headers=RAVI).json()["viewer_can_manage"] is True
    stats = client.get(f"{API}/companies/{company['id']}/hiring-stats").json()
    assert stats["years"] == [] and stats["total_selected"] == 0


def test_only_placement_moderators_manage_companies(client, placement):
    assert client.post(f"{API}/companies", headers=ASHA, json={"name": "Google"}).status_code == 403
    assert client.post(f"{API}/companies", json={"name": "Google"}).status_code == 401
    company = _company(client, "Google")
    assert client.patch(f"{API}/companies/{company['id']}", headers=ASHA, json={"industry": "x"}).status_code == 403
    assert client.post(f"{API}/companies/{company['id']}/jds", headers=ASHA,
                       json={"role_title": "SWE"}).status_code == 403
    assert client.post(f"{API}/companies/{company['id']}/ppts", headers=ASHA,
                       json={"venue": "Faculty Hall"}).status_code == 403
    # Same name in another case/spacing is the same company.
    assert client.post(f"{API}/companies", headers=RAVI, json={"name": " google "}).status_code == 409
    assert client.post(f"{API}/companies", headers=RAVI,
                       json={"name": "X", "website": "javascript:alert(1)"}).status_code == 422
    # Moderators edit; only the admin deletes (it takes the hiring records with it).
    r = client.patch(f"{API}/companies/{company['id']}", headers=RAVI, json={"industry": "Search and cloud"})
    assert r.status_code == 200 and r.json()["industry"] == "Search and cloud"
    assert client.delete(f"{API}/companies/{company['id']}", headers=RAVI).status_code == 403
    assert client.delete(f"{API}/companies/{company['id']}", headers=ADMIN).status_code == 204
    assert client.get(f"{API}/companies/{company['id']}").status_code == 404


def test_revoked_moderator_loses_access(client, placement):
    """FR-3: a revoked moderator's next privileged call is rejected."""
    grant_id = client.get(f"{API}/moderators", headers=ADMIN, params={"module": "placement_hub"}).json()[0]["id"]
    assert client.delete(f"{API}/moderators/{grant_id}", headers=ADMIN).status_code in (200, 204)
    assert client.post(f"{API}/companies", headers=RAVI, json={"name": "Intel"}).status_code == 403


def test_job_descriptions_and_ppts(client, s3, placement):
    company = _company(client)
    key = upload(client, s3, RAVI, "job_description", b"%PDF-1.4 jd", "application/pdf")
    r = client.post(f"{API}/companies/{company['id']}/jds", headers=RAVI, json={
        "role_title": "Software Engineer", "description": "Backend services in Java.",
        "compensation": "₹32 LPA", "file_s3_key": key})
    assert r.status_code == 201, r.text
    jd = r.json()
    assert jd["file_url"] and jd["compensation"] == "₹32 LPA"
    # Students can't even get a JD upload ticket.
    r = client.post(f"{API}/uploads", headers=ASHA, json={
        "kind": "job_description", "content_type": "application/pdf", "size_bytes": 10,
        "checksum_sha256": "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="})
    assert r.status_code == 403
    r = client.patch(f"{API}/jds/{jd['id']}", headers=RAVI, json={"file_s3_key": None, "compensation": ""})
    assert r.status_code == 200 and r.json()["file_url"] is None and r.json()["compensation"] is None

    soon = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    long_ago = (datetime.now(timezone.utc) - timedelta(days=200)).isoformat()
    assert client.post(f"{API}/companies/{company['id']}/ppts", headers=RAVI, json={}).status_code == 422
    upcoming = client.post(f"{API}/companies/{company['id']}/ppts", headers=RAVI,
                           json={"details": "Roles and process", "venue": "Faculty Hall", "scheduled_at": soon}).json()
    past = client.post(f"{API}/companies/{company['id']}/ppts", headers=RAVI,
                       json={"venue": "CDS 102", "scheduled_at": long_ago}).json()
    assert (upcoming["when"], past["when"]) == ("upcoming", "past")
    page = client.get(f"{API}/companies/{company['id']}").json()
    assert page["role_count"] == 1 and page["next_ppt_at"] is not None and len(page["ppts"]) == 2
    feed = client.get(f"{API}/placement/ppts").json()["items"]
    assert [p["id"] for p in feed] == [upcoming["id"]] and feed[0]["company_name"] == "Walmart Global Tech"
    assert client.delete(f"{API}/ppts/{past['id']}", headers=RAVI).status_code == 204
    assert client.delete(f"{API}/jds/{jd['id']}", headers=RAVI).status_code == 204
    assert client.get(f"{API}/companies/{company['id']}").json()["job_descriptions"] == []


def test_company_search_and_sort(client, placement):
    _company(client, "Goldman Sachs", industry="Finance")
    _company(client, "Google", industry="Software")
    _company(client, "Qualcomm", industry="Semiconductors")
    names = lambda **p: [c["name"] for c in client.get(f"{API}/companies", params=p).json()["items"]]  # noqa: E731
    assert names() == ["Goldman Sachs", "Google", "Qualcomm"]
    assert names(q="goo") == ["Google"]
    assert names(q="finance") == ["Goldman Sachs"]
    assert names(q="%") == []                       # wildcards are literal
    assert names(industry="software") == ["Google"]


# ---------------------------------------------------------------- bulk import + statistics (FR-17, FR-15)
SHEET = """Slot\tCompany\tStudent email\tRole
Slot 1\tWalmart Global Tech\tchandu@iisc.ac.in\tSoftware Engineer
Slot 1\tWalmart Global Tech\tasha@iisc.ac.in\tData Scientist
Slot 2\tgoogle\tmeera@iisc.ac.in\tSoftware Engineer
\t\t\t
Slot 2\tGoogle\tsomeone@gmail.com\tSWE
Slot 3\t\tkiran@iisc.ac.in\tSWE
Slot 3\tGoogle\tchandu@iisc.ac.in\tSWE
Slot 3\tGoogle\tkiran@iisc.ac.in\t
"""


def test_parse_sheet_reports_every_bad_row():
    rows, rejected = parse_sheet(SHEET)
    assert [r.email for r in rows] == ["chandu@iisc.ac.in", "asha@iisc.ac.in", "meera@iisc.ac.in"]
    assert [(r.line, r.reason.split()[0]) for r in rejected] == [(6, "“someone@gmail.com”"), (7, "Company"),
                                                                (8, "Same"), (9, "Role")]
    rows, _ = parse_sheet("email,company,role\nA@IISC.AC.IN , Intel ,  GPU   engineer\n")   # CSV, any order
    assert (rows[0].email, rows[0].company, rows[0].role, rows[0].slot) == ("a@iisc.ac.in", "Intel", "GPU engineer", None)
    with pytest.raises(SheetError, match="Missing: Role"):
        parse_sheet("Company,Email\nIntel,a@iisc.ac.in")
    with pytest.raises(SheetError):
        parse_sheet("   \n\n")


def test_import_creates_updates_and_rejects(client, s3, placement):
    walmart = _company(client)
    assert client.post(f"{API}/placement/imports", headers=ASHA,
                       json={"placement_year": 2026, "sheet": SHEET}).status_code == 403
    r = client.post(f"{API}/placement/imports", headers=RAVI, json={"placement_year": 2026, "sheet": SHEET})
    assert r.status_code == 201, r.text
    result = r.json()
    assert (result["rows_total"], result["rows_created"], result["rows_updated"], result["rows_rejected"]) == (7, 3, 0, 4)
    assert result["companies_created"] == ["google"]
    assert [row["line"] for row in result["rejected_rows"]] == [6, 7, 8, 9]
    # The pasted sheet is kept in S3 as the import's source.
    key = sql("SELECT source_s3_key FROM placement_bulk_imports")[0]["source_s3_key"]
    assert b"Walmart" in s3.get_object(Bucket="campushub-test", Key=key)["Body"].read()

    # Re-importing an edited sheet updates instead of duplicating (Chandu moves to Google).
    r = client.post(f"{API}/placement/imports", headers=RAVI, json={"placement_year": 2026, "sheet":
        "Company,Student email,Role\nGoogle,chandu@iisc.ac.in,Research Engineer\nGoogle,new@iisc.ac.in,SWE\n"}).json()
    assert (r["rows_created"], r["rows_updated"], r["rows_rejected"], r["companies_created"]) == (1, 1, 0, [])
    client.post(f"{API}/placement/imports", headers=RAVI, json={"placement_year": 2025, "sheet":
        "Company,Student email,Role\nWalmart Global Tech,old@iisc.ac.in,Software Engineer\n"})

    stats = client.get(f"{API}/companies/{walmart['id']}/hiring-stats").json()
    assert stats["total_selected"] == 2
    assert [(y["year"], y["students_selected"]) for y in stats["years"]] == [(2026, 1), (2025, 1)]
    assert stats["years"][0]["roles"] == [{"role_title": "Data Scientist", "students_selected": 1}]
    assert "chandu" not in str(stats) and "asha" not in str(stats)       # totals only, never students

    overview = client.get(f"{API}/placement/stats").json()
    assert [(s["year"], s["students_selected"], s["companies"]) for s in overview["seasons"]] == [(2026, 4, 2), (2025, 1, 1)]
    assert overview["year"] == 2026 and overview["top_companies"][0]["company_name"] == "google"
    assert overview["top_companies"][0]["students_selected"] == 3
    page = client.get(f"{API}/companies/{walmart['id']}").json()
    assert (page["latest_year"], page["latest_year_selected"], page["total_selected"]) == (2026, 1, 2)
    history = client.get(f"{API}/placement/imports", headers=RAVI).json()["items"]
    assert len(history) == 3 and history[0]["moderator"]["name"] == "Ravi"
    assert client.get(f"{API}/placement/imports", headers=ASHA).status_code == 403


def test_import_needs_file_storage(client, placement, monkeypatch):
    """The pasted sheet is kept in S3; if storage is down, nothing is imported and the moderator is told why."""
    from botocore.exceptions import EndpointConnectionError

    from app.routers import placement as placement_router

    async def down(*_args, **_kwargs):
        raise EndpointConnectionError(endpoint_url="http://localhost:9000")
    monkeypatch.setattr(placement_router, "put_object", down)
    r = client.post(f"{API}/placement/imports", headers=RAVI,
                    json={"placement_year": 2026, "sheet": "Company,Email,Role\nIntel,a@iisc.ac.in,SWE"})
    assert r.status_code == 503 and "storage" in r.json()["detail"]
    assert sql("SELECT count(*) AS n FROM placement_records")[0]["n"] == 0


def test_import_rejects_unreadable_sheet(client, placement):
    r = client.post(f"{API}/placement/imports", headers=RAVI,
                    json={"placement_year": 2026, "sheet": "Name,Email\nA,a@iisc.ac.in"})
    assert r.status_code == 422 and "Company" in r.json()["detail"]
    assert sql("SELECT count(*) AS n FROM placement_bulk_imports")[0]["n"] == 0


# ---------------------------------------------------------------- interview experiences (FR-16)
def test_interview_experiences(client, placement):
    company = _company(client)
    assert client.post(f"{API}/companies/{company['id']}/interviews",
                       json={"role_title": "SDE", "content": "x"}).status_code == 401
    r = client.post(f"{API}/companies/{company['id']}/interviews", headers=ASHA, json={
        "role_title": "SDE", "placement_year": 2026, "content": "Two DSA rounds and a system design round.",
        "is_anonymous": True})
    assert r.status_code == 201, r.text
    anon = r.json()
    assert anon["is_mine"] and anon["author"]["name"] == "Asha"                # the author sees their name
    named = client.post(f"{API}/companies/{company['id']}/interviews", headers=MEERA, json={
        "role_title": "Data Scientist", "content": "ML theory and a case study."}).json()

    # Visible under the company page, newest first; names hidden from guests and for anonymous posts.
    feed = client.get(f"{API}/interviews", params={"company_id": company["id"]}, headers=KIRAN).json()["items"]
    assert [i["id"] for i in feed] == [named["id"], anon["id"]]
    assert feed[0]["author"]["name"] == "Meera" and feed[1]["author"] is None
    assert all(i["author"] is None for i in client.get(f"{API}/interviews").json()["items"])
    assert client.get(f"{API}/companies/{company['id']}").json()["interview_count"] == 2
    assert [i["id"] for i in client.get(f"{API}/interviews", params={"q": "case study"}).json()["items"]] == [named["id"]]
    assert [i["id"] for i in client.get(f"{API}/interviews", params={"mine": True}, headers=ASHA).json()["items"]] == [anon["id"]]

    # Only the author edits (the admin may fix text but not reveal an anonymous author).
    assert client.patch(f"{API}/interviews/{anon['id']}", headers=KIRAN, json={"content": "x"}).status_code == 403
    assert client.patch(f"{API}/interviews/{anon['id']}", headers=ADMIN, json={"is_anonymous": False}).status_code == 403
    assert client.patch(f"{API}/interviews/{anon['id']}", headers=ADMIN, json={"content": "Edited."}).status_code == 200
    # Reported, then removed by a Placement Hub moderator: the report closes.
    assert client.post(f"{API}/reports", headers=KIRAN, json={
        "target_type": "interview_experience", "target_id": named["id"], "reason": "Shares NDA questions"}).status_code == 201
    assert client.get(f"{API}/reports", headers=RAVI).json()["items"][0]["target_id"] == named["id"]
    assert client.delete(f"{API}/interviews/{named['id']}", headers=KIRAN).status_code == 403
    assert client.delete(f"{API}/interviews/{named['id']}", headers=RAVI).status_code == 204
    assert client.get(f"{API}/reports", headers=RAVI).json()["items"] == []
    assert client.get(f"{API}/interviews/{named['id']}").status_code == 404


def test_company_forum(client, placement):
    company = _company(client)
    forum = client.get(f"{API}/companies/{company['id']}/forum").json()
    assert forum["scope_type"] == "company" and forum["company_id"] == company["id"]
    assert client.get(f"{API}/companies/{company['id']}/forum").json()["id"] == forum["id"]
    thread = client.post(f"{API}/forums/{forum['id']}/threads", headers=ASHA,
                         json={"title": "OA cut-off?", "content": "What was the cut-off last year?"}).json()
    # A Placement Hub moderator can remove posts in a company forum; an Academic Help one can't.
    assert client.get(f"{API}/threads/{thread['id']}", headers=RAVI).json()["viewer_can_moderate"] is True
    assert client.get(f"{API}/threads/{thread['id']}", headers=MEERA).json()["viewer_can_moderate"] is False
    assert client.delete(f"{API}/threads/{thread['id']}", headers=RAVI).status_code == 204
    assert client.get(f"{API}/companies/00000000-0000-0000-0000-000000000000/forum").status_code == 404
