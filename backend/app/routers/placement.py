"""Placement Hub (FR-15, FR-16, FR-17): company pages, job descriptions, pre-placement talks,
hiring statistics, interview experiences and the bulk import of placement sheets.

  guest                     season totals only (students selected and companies hiring per year, no
                            company names or pay) on GET /placement/stats; everything else needs sign-in
  user                      read companies, their JDs/PPTs/hiring stats and interview experiences
                            (hiring statistics are totals only, never students); post interview
                            experiences (optionally anonymous); edit/delete their own
  placement_hub moderator   add/edit companies, JDs and the placement schedule (PPTs, online tests,
                            interviews); import placement sheets, company lists and schedules as CSV;
                            remove anyone's interview experience (and company forum posts)
  admin                     all of the above, and delete a company with everything under it

Each company also has a forum (GET /companies/{id}/forum in forums.py).
"""
import uuid
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID

import asyncpg
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, field_validator

from ..auth import CurrentUser, current_user, optional_user
from ..common import (Page, PageParams, UserRef, forbidden, like_pattern, make_page, not_found, page_params,
                      search_text, set_clause, text)
from ..company_matching import group_similar, suggested_name
from ..db import get_conn
from ..permissions import close_reports, is_module_moderator, log_moderation
from ..placement_csv import parse_companies, parse_schedule
from ..placement_roles import parse_inr, parse_roles
from ..placement_sheet import SheetError, parse_sheet
from ..storage import delete_objects, file_url, mark_attached, put_object, verify_own_uploads

router = APIRouter(tags=["Placement Hub"])

MODULE = "placement_hub"
PptKind = Literal["ppt", "oa", "interview", "other"]
KIND_NAMES = {"ppt": "Pre-placement talk", "oa": "Online test", "interview": "Interviews", "other": "Placement date"}
Year = Field(ge=2000, le=2100)


def _check_url(value: str | None) -> str | None:
    if value and not value.lower().startswith(("https://", "http://")):
        raise ValueError("must start with https://")
    return value


# ---------------------------------------------------------------- models
class CompanyCreate(BaseModel):
    name: text(120, single_line=True) = Field(examples=["Walmart Global Tech"])
    description: text(5000, min_length=0) | None = None
    website: text(300, min_length=0) | None = Field(None, examples=["https://careers.walmart.com"])
    industry: text(80, min_length=0) | None = Field(None, examples=["Retail technology"])

    _url = field_validator("website")(_check_url)


class CompanyUpdate(BaseModel):
    name: text(120, single_line=True) | None = None
    description: text(5000, min_length=0) | None = None
    website: text(300, min_length=0) | None = None
    industry: text(80, min_length=0) | None = None

    _url = field_validator("website")(_check_url)


JobType = Literal["full_time", "internship", "ppo", "other"]


class JobDescriptionIn(BaseModel):
    role_title: text(200, single_line=True) = Field(examples=["Software Engineer"])
    description: text(20_000, min_length=0) | None = Field(None, description="The JD as text")
    compensation: text(200, min_length=0) | None = Field(
        None, examples=["₹32 LPA"], description="As announced; the amount is read from it (ctc_min / ctc_max)")
    placement_year: int | None = Field(None, ge=2000, le=2100, description="The season, e.g. 2026 for 2025-26")
    job_type: JobType = "full_time"
    base: text(200, min_length=0) | None = Field(None, description="Base / fixed pay, as announced")
    skills: text(5000, min_length=0) | None = None
    file_s3_key: str | None = Field(None, description="Optional JD file: s3_key from POST /uploads "
                                                      "(kind job_description)")


class JobDescriptionUpdate(BaseModel):
    role_title: text(200, single_line=True) | None = None
    description: text(20_000, min_length=0) | None = None
    compensation: text(200, min_length=0) | None = None
    placement_year: int | None = Field(None, ge=2000, le=2100)
    job_type: JobType | None = None
    base: text(200, min_length=0) | None = None
    skills: text(5000, min_length=0) | None = None
    file_s3_key: str | None = Field(None, description="A new file's s3_key, or null to remove the file")


class PptIn(BaseModel):
    kind: PptKind = Field("ppt", description="ppt: pre-placement talk, oa: online test, interview, other")
    details: text(5000, min_length=0) | None = None
    venue: text(200, min_length=0) | None = Field(None, examples=["Faculty Hall"])
    scheduled_at: datetime | None = Field(None, description="Leave out while the date isn't announced")


class PptUpdate(BaseModel):
    kind: PptKind | None = None
    details: text(5000, min_length=0) | None = None
    venue: text(200, min_length=0) | None = None
    scheduled_at: datetime | None = None


class InterviewCreate(BaseModel):
    role_title: text(200, single_line=True) = Field(examples=["SDE"])
    placement_year: int | None = Field(None, ge=2000, le=2100, description="The placement season, e.g. 2026")
    content: text(20_000) = Field(description="Rounds, questions, tips")
    is_anonymous: bool = Field(False, description="Hide your name from everyone else")


class InterviewUpdate(BaseModel):
    role_title: text(200, single_line=True) | None = None
    placement_year: int | None = Field(None, ge=2000, le=2100)
    content: text(20_000) | None = None
    is_anonymous: bool | None = None


class CsvImportRequest(BaseModel):
    csv: str = Field(min_length=1, max_length=2_000_000, description="CSV or tab-separated text with a header row")
    file_name: str | None = Field(None, max_length=255, description="Placement dates: the file's name. When neither "
                                  "a Type column nor the column names say the round, \"interview\", \"test\" or "
                                  "\"PPT\" in it does (\"slot 2 interview schedule.csv\").")


class ImportRequest(BaseModel):
    placement_year: int = Field(ge=2000, le=2100, description="The season the sheet is for; the sheet has no year")
    sheet: str = Field(min_length=1, max_length=2_000_000,
                       description="The sheet as CSV or tab-separated text (cells copied from a spreadsheet). "
                                   "Header row with Company, Student email, Role and optionally Slot.")


class JobDescription(BaseModel):
    id: UUID
    company_id: UUID
    role_title: str
    description: str | None
    compensation: str | None = Field(description="As announced, e.g. '₹32 LPA' or 'Refer JD'")
    ctc_min: int | None = Field(None, description="Rupees a year read from compensation (null if it has no amount)")
    ctc_max: int | None = Field(None, description="Same as ctc_min unless compensation is a range")
    base: str | None = Field(None, description="Base / fixed pay, as announced")
    base_annual: int | None = None
    placement_year: int | None = Field(None, description="The season the role was offered in")
    job_type: JobType = "full_time"
    skills: str | None = None
    file_s3_key: str | None
    file_url: str | None = Field(description="Short-lived download link for the JD file")
    created_at: datetime
    updated_at: datetime


class Ppt(BaseModel):
    """One date on the placement schedule: a pre-placement talk, online test, interviews or other."""
    id: UUID
    company_id: UUID
    company_name: str
    kind: PptKind
    details: str | None
    venue: str | None
    scheduled_at: datetime | None
    time_tbd: bool = Field(False, description="Only the day is known (imported without a time): show it without a time")
    when: Literal["upcoming", "past", "unscheduled"]
    created_at: datetime
    updated_at: datetime


class CompanySummary(BaseModel):
    id: UUID
    name: str
    industry: str | None
    description: str | None
    role_count: int = Field(description="Job descriptions on file")
    interview_count: int
    next_ppt_at: datetime | None = Field(description="The next scheduled pre-placement talk, if any")
    next_date_at: datetime | None = Field(None, description="The next date of any kind on its schedule")
    next_date_kind: PptKind | None = Field(None, description="What next_date_at is")
    latest_year: int | None = Field(description="The latest placement year with hires")
    latest_year_selected: int = Field(description="Students selected in latest_year")
    total_selected: int = Field(description="Students selected across all imported years")
    ctc_year: int | None = Field(None, description="The latest season with a known compensation")
    ctc_min: int | None = Field(None, description="Lowest compensation offered in ctc_year, rupees a year")
    ctc_max: int | None = Field(None, description="Highest compensation offered in ctc_year, rupees a year")


class CompanyDetail(CompanySummary):
    website: str | None
    job_descriptions: list[JobDescription] = Field(description="Empty list = no JD yet (show an empty state)")
    ppts: list[Ppt] = Field(description="The company's schedule (talks, tests, interviews), newest first")
    viewer_can_manage: bool = Field(description="True for Placement Hub moderators and admins")
    created_at: datetime
    updated_at: datetime


class RoleCount(BaseModel):
    role_title: str
    students_selected: int


class YearStats(BaseModel):
    year: int
    students_selected: int
    roles: list[RoleCount] = Field(description="Most hires first")


class HiringStats(BaseModel):
    company_id: UUID
    company_name: str
    total_selected: int
    years: list[YearStats] = Field(description="Newest year first; empty when no sheet mentions the company")


class SeasonStats(BaseModel):
    year: int
    students_selected: int
    companies: int


class TopCompany(BaseModel):
    company_id: UUID
    company_name: str
    students_selected: int
    ctc_min: int | None = Field(None, description="Lowest full-time compensation offered that season, rupees a year")
    ctc_max: int | None = None


class CompanyPay(BaseModel):
    company_id: UUID
    company_name: str
    ctc_min: int = Field(description="Rupees a year")
    ctc_max: int
    roles: int = Field(description="Roles with a known compensation that season")


class PlacementOverview(BaseModel):
    seasons: list[SeasonStats] = Field(description="Newest first")
    year: int | None = Field(description="The season top_companies is for")
    top_companies: list[TopCompany]
    pay_year: int | None = Field(None, description="The latest season with compensation data")
    top_paying: list[CompanyPay] = Field(default_factory=list,
                                         description="Full-time roles in pay_year, highest compensation first")


class Interview(BaseModel):
    id: UUID
    company_id: UUID
    company_name: str
    role_title: str | None
    placement_year: int | None
    content: str
    is_anonymous: bool
    is_mine: bool
    author: UserRef | None = Field(description="null for anonymous posts (except to their author) and for guests")
    created_at: datetime
    updated_at: datetime


class RejectedRowOut(BaseModel):
    line: int = Field(description="Line in the pasted sheet; the header is line 1")
    reason: str


class SimilarCompany(BaseModel):
    id: UUID
    name: str
    records: int = Field(description="Placement records (selected students) under this name")


class SimilarCompanyGroup(BaseModel):
    suggested_name: str = Field(description="A clean name for the merged company; the reviewer can change it")
    companies: list[SimilarCompany]


class CompanyMerge(BaseModel):
    company_ids: list[UUID] = Field(min_length=2, max_length=50)
    name: str = Field(min_length=1, max_length=200, description="The merged company's name")


class ImportResult(BaseModel):
    id: UUID
    placement_year: int
    rows_total: int
    rows_created: int
    rows_updated: int
    rows_rejected: int
    companies_created: list[str]
    rejected_rows: list[RejectedRowOut]
    imported_at: datetime
    similar_companies: list[SimilarCompanyGroup] = Field(
        default_factory=list, description="Companies in this sheet that are probably the same as another company "
                                          "(e.g. \"Accenture [Mock Assessment]\" and \"Accenture\"), for review")


class CsvImportResult(BaseModel):
    rows_total: int
    rows_created: int
    rows_updated: int
    rows_rejected: int
    companies_created: list[str]
    rejected_rows: list[RejectedRowOut]
    kinds: dict[str, int] = Field(default_factory=dict,
                                  description="Schedule imports: rows saved per type, e.g. {\"interview\": 7}")
    past_rows: int = Field(0, description="Schedule imports: saved dates that have already passed")


class ImportSummary(BaseModel):
    id: UUID
    placement_year: int
    rows_total: int
    rows_created: int
    rows_updated: int
    rows_rejected: int
    moderator: UserRef
    imported_at: datetime


# ---------------------------------------------------------------- helpers
async def _require_moderator(conn: asyncpg.Connection, user: CurrentUser) -> None:
    if not await is_module_moderator(conn, user, MODULE):
        raise forbidden("Only Placement Hub moderators can do this.")


async def _company_exists(conn: asyncpg.Connection, company_id: UUID) -> None:
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM companies WHERE id = $1)", company_id):
        raise not_found("Company")


_COMPANY_SELECT = """
SELECT c.id, c.name, c.industry, c.description, c.website, c.created_at, c.updated_at,
       (SELECT count(*) FROM job_descriptions j WHERE j.company_id = c.id) AS role_count,
       (SELECT count(*) FROM interview_experiences i WHERE i.company_id = c.id AND i.deleted_at IS NULL)
           AS interview_count,
       (SELECT min(p.scheduled_at) FROM ppt_info p
        WHERE p.company_id = c.id AND p.kind = 'ppt' AND p.scheduled_at >= now()) AS next_ppt_at,
       nd.next_date_at, nd.next_date_kind,
       ly.latest_year, coalesce(ly.latest_year_selected, 0) AS latest_year_selected,
       (SELECT count(*) FROM placement_records r WHERE r.company_id = c.id) AS total_selected,
       pay.ctc_year, pay.ctc_min, pay.ctc_max
FROM companies c
LEFT JOIN LATERAL (
    SELECT j.placement_year AS ctc_year, min(j.ctc_min) AS ctc_min, max(j.ctc_max) AS ctc_max
    FROM job_descriptions j WHERE j.company_id = c.id AND j.ctc_min IS NOT NULL AND j.job_type <> 'internship'
    GROUP BY j.placement_year ORDER BY j.placement_year DESC NULLS LAST LIMIT 1
) pay ON true
LEFT JOIN LATERAL (
    SELECT r.placement_year AS latest_year, count(*) AS latest_year_selected
    FROM placement_records r WHERE r.company_id = c.id
    GROUP BY r.placement_year ORDER BY r.placement_year DESC LIMIT 1
) ly ON true
LEFT JOIN LATERAL (
    SELECT p.scheduled_at AS next_date_at, p.kind AS next_date_kind
    FROM ppt_info p WHERE p.company_id = c.id AND p.scheduled_at >= now()
    ORDER BY p.scheduled_at LIMIT 1
) nd ON true
"""


def _company_summary(r: asyncpg.Record) -> CompanySummary:
    return CompanySummary(id=r["id"], name=r["name"], industry=r["industry"], description=r["description"],
                          role_count=r["role_count"], interview_count=r["interview_count"],
                          next_ppt_at=r["next_ppt_at"], next_date_at=r["next_date_at"],
                          next_date_kind=r["next_date_kind"], latest_year=r["latest_year"],
                          latest_year_selected=r["latest_year_selected"], total_selected=r["total_selected"],
                          ctc_year=r["ctc_year"], ctc_min=r["ctc_min"], ctc_max=r["ctc_max"])


def _jd(r: asyncpg.Record) -> JobDescription:
    key = r["jd_s3_key"]
    return JobDescription(id=r["id"], company_id=r["company_id"], role_title=r["role_title"],
                          description=r["description"], compensation=r["compensation"], ctc_min=r["ctc_min"],
                          ctc_max=r["ctc_max"], base=r["base_text"], base_annual=r["base_annual"],
                          placement_year=r["placement_year"], job_type=r["job_type"], skills=r["skills"],
                          file_s3_key=key,
                          file_url=file_url(key) if key else None, created_at=r["created_at"],
                          updated_at=r["updated_at"])


_PPT_SELECT = """
SELECT p.id, p.company_id, c.name AS company_name, p.kind, p.details, p.venue, p.scheduled_at, p.time_tbd,
       p.created_at, p.updated_at
FROM ppt_info p JOIN companies c ON c.id = p.company_id
"""


def _ppt(r: asyncpg.Record) -> Ppt:
    at = r["scheduled_at"]
    when = "unscheduled" if at is None else ("upcoming" if at >= datetime.now(timezone.utc) else "past")
    return Ppt(id=r["id"], company_id=r["company_id"], company_name=r["company_name"], kind=r["kind"],
               details=r["details"],
               venue=r["venue"], scheduled_at=at, time_tbd=r["time_tbd"], when=when, created_at=r["created_at"], updated_at=r["updated_at"])


async def _company_detail(conn: asyncpg.Connection, company_id: UUID, viewer: CurrentUser | None) -> CompanyDetail:
    r = await conn.fetchrow(_COMPANY_SELECT + " WHERE c.id = $1", company_id)
    if r is None:
        raise not_found("Company")
    jds = await conn.fetch("SELECT * FROM job_descriptions WHERE company_id = $1 ORDER BY role_title, id", company_id)
    ppts = await conn.fetch(
        _PPT_SELECT + " WHERE p.company_id = $1 ORDER BY p.scheduled_at DESC NULLS FIRST, p.created_at DESC",
        company_id)
    can_manage = bool(viewer) and await is_module_moderator(conn, viewer, MODULE)
    return CompanyDetail(**_company_summary(r).model_dump(), website=r["website"],
                         job_descriptions=[_jd(j) for j in jds], ppts=[_ppt(p) for p in ppts],
                         viewer_can_manage=can_manage, created_at=r["created_at"], updated_at=r["updated_at"])


# ---------------------------------------------------------------- companies
@router.get("/companies", response_model=Page[CompanySummary],
            summary="Browse companies, with their hiring numbers and pay (signed in only)")
async def list_companies(
    q: str | None = Query(None, max_length=200, description="Words in the company name or industry"),
    industry: str | None = Query(None, max_length=80),
    sort: Literal["name", "most_hired", "upcoming_ppt", "highest_pay"] = Query(
        "name", description="most_hired: by students selected in their latest season; "
                            "upcoming_ppt: companies with the soonest talk first; "
                            "highest_pay: by the top compensation of their latest season with pay data"),
    page: PageParams = Depends(page_params),
    user: CurrentUser = Depends(current_user),
    conn: asyncpg.Connection = Depends(get_conn),
):
    order = {
        "name": "lower(x.name), x.id",
        "most_hired": "x.latest_year DESC NULLS LAST, x.latest_year_selected DESC, lower(x.name), x.id",
        "upcoming_ppt": "x.next_date_at ASC NULLS LAST, lower(x.name), x.id",
        "highest_pay": "x.ctc_max DESC NULLS LAST, lower(x.name), x.id",
    }[sort]
    q = search_text(q)
    rows = await conn.fetch(
        f"""SELECT * FROM ({_COMPANY_SELECT}) x
        WHERE ($1::text IS NULL OR x.name ILIKE '%' || $1 || '%' ESCAPE '\\'
                                OR x.industry ILIKE '%' || $1 || '%' ESCAPE '\\')
          AND ($2::text IS NULL OR lower(x.industry) = lower($2))
        ORDER BY {order} LIMIT $3 OFFSET $4""",
        like_pattern(q) if q else None, search_text(industry), page.limit + 1, page.offset)
    return make_page(rows, page, _company_summary)


@router.get("/companies/{company_id}", response_model=CompanyDetail,
            summary="A company page: details, JDs, PPTs and headline numbers (signed in only)")
async def get_company(company_id: UUID, user: CurrentUser = Depends(current_user),
                      conn: asyncpg.Connection = Depends(get_conn)):
    return await _company_detail(conn, company_id, user)


@router.post("/companies", response_model=CompanyDetail, status_code=201,
             summary="Add a company (Placement Hub moderator or admin)")
async def create_company(body: CompanyCreate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    try:
        company_id = await conn.fetchval(
            """INSERT INTO companies (name, description, website, industry, created_by) VALUES ($1, $2, $3, $4, $5)
               RETURNING id""",
            body.name, body.description or None, body.website or None, body.industry or None, user.id)
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, f"A company called “{body.name}” already exists.") from exc
    return await _company_detail(conn, company_id, user)


@router.patch("/companies/{company_id}", response_model=CompanyDetail,
              summary="Edit a company (Placement Hub moderator or admin)")
async def update_company(company_id: UUID, body: CompanyUpdate, user: CurrentUser = Depends(current_user),
                         conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    await _company_exists(conn, company_id)
    changes = body.model_dump(exclude_unset=True)
    if "name" in changes and changes["name"] is None:
        raise HTTPException(422, "name can't be empty.")
    changes = {k: (v or None) for k, v in changes.items()}
    sql, values = set_clause(changes, start=2)
    try:
        async with conn.transaction():
            await conn.execute(f"UPDATE companies SET {sql} WHERE id = $1", company_id, *values)
            await log_moderation(conn, user.id, "edit_company", "company", company_id)
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, "Another company already has that name.") from exc
    return await _company_detail(conn, company_id, user)


@router.delete("/companies/{company_id}", status_code=204,
               summary="Delete a company with everything under it (Placement Hub moderator or admin)")
async def delete_company(company_id: UUID, reason: str | None = Query(None, max_length=500),
                         user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    """For a company that withdrew: its roles and JD files, every date on its schedule (upcoming PPTs, tests and
    interviews included), hiring records, seniors, interview experiences and its forum all go. Open reports
    about its interview experiences and forum posts are closed."""
    await _require_moderator(conn, user)
    keys = [r["jd_s3_key"] for r in await conn.fetch(
        "SELECT jd_s3_key FROM job_descriptions WHERE company_id = $1 AND jd_s3_key IS NOT NULL", company_id)]
    async with conn.transaction():
        interviews = [r["id"] for r in await conn.fetch(
            "SELECT id FROM interview_experiences WHERE company_id = $1", company_id)]
        threads = [r["id"] for r in await conn.fetch(
            "SELECT t.id FROM threads t JOIN forums f ON f.id = t.forum_id WHERE f.company_id = $1", company_id)]
        comments = [r["id"] for r in await conn.fetch(
            "SELECT c.id FROM comments c WHERE c.thread_id = ANY($1::uuid[])", threads)]
        await close_reports(conn, "interview_experience", interviews, user.id, reason or "Company removed")
        await close_reports(conn, "thread", threads, user.id, reason or "Company removed")
        await close_reports(conn, "comment", comments, user.id, reason or "Company removed")
        deleted = await conn.fetchval("DELETE FROM companies WHERE id = $1 RETURNING true", company_id)
        if not deleted:
            raise not_found("Company")
        await log_moderation(conn, user.id, "delete_company", "company", company_id, reason)
    await delete_objects(keys)
    return Response(status_code=204)


# ---------------------------------------------------------------- job descriptions
async def _jd_detail(conn: asyncpg.Connection, jd_id: UUID) -> JobDescription:
    r = await conn.fetchrow("SELECT * FROM job_descriptions WHERE id = $1", jd_id)
    if r is None:
        raise not_found("Job description")
    return _jd(r)


@router.post("/companies/{company_id}/jds", response_model=JobDescription, status_code=201,
             summary="Add a job description (Placement Hub moderator or admin)")
async def create_jd(company_id: UUID, body: JobDescriptionIn, user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    await _company_exists(conn, company_id)
    if body.file_s3_key:
        await verify_own_uploads([body.file_s3_key], "job_description", user.id)
    ctc = parse_inr(body.compensation)
    base = parse_inr(body.base)
    try:
        jd_id = await conn.fetchval(
            """INSERT INTO job_descriptions (company_id, role_title, description, compensation, jd_s3_key, placement_year,
                                             job_type, ctc_min, ctc_max, base_text, base_annual, skills)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING id""",
            company_id, body.role_title, body.description or None, body.compensation or None, body.file_s3_key,
            body.placement_year, body.job_type, ctc[0] if ctc else None, ctc[1] if ctc else None, body.base or None,
            base[1] if base else None, body.skills or None)
    except asyncpg.UniqueViolationError as exc:
        raise HTTPException(409, "This company already has that role for that season. Edit it instead.") from exc
    if body.file_s3_key:
        await mark_attached([body.file_s3_key])
    return await _jd_detail(conn, jd_id)


@router.patch("/jds/{jd_id}", response_model=JobDescription,
              summary="Edit a job description (Placement Hub moderator or admin)")
async def update_jd(jd_id: UUID, body: JobDescriptionUpdate, user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    old_key = await conn.fetchval("SELECT jd_s3_key FROM job_descriptions WHERE id = $1", jd_id)
    if old_key is None and not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM job_descriptions WHERE id = $1)",
                                                   jd_id):
        raise not_found("Job description")
    changes = body.model_dump(exclude_unset=True)
    if "role_title" in changes and changes["role_title"] is None:
        raise HTTPException(422, "role_title can't be empty.")
    new_key = changes.pop("file_s3_key", old_key)
    if new_key and new_key != old_key:
        await verify_own_uploads([new_key], "job_description", user.id)
    if new_key != old_key:
        changes["jd_s3_key"] = new_key
    changes = {k: (v or None) if k in ("description", "compensation", "base", "skills") else v
               for k, v in changes.items()}
    if "job_type" in changes and changes["job_type"] is None:
        raise HTTPException(422, "job_type can't be empty.")
    if "compensation" in changes:
        ctc = parse_inr(changes["compensation"])
        changes["ctc_min"], changes["ctc_max"] = ctc if ctc else (None, None)
    if "base" in changes:
        base = parse_inr(changes["base"])
        changes["base_text"] = changes.pop("base")
        changes["base_annual"] = base[1] if base else None
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        try:
            await conn.execute(f"UPDATE job_descriptions SET {sql} WHERE id = $1", jd_id, *values)
        except asyncpg.UniqueViolationError as exc:
            raise HTTPException(409, "This company already has that role for that season.") from exc
        await log_moderation(conn, user.id, "edit_job_description", "job_description", jd_id)
    if new_key != old_key:
        if new_key:
            await mark_attached([new_key])
        if old_key:
            await delete_objects([old_key])
    return await _jd_detail(conn, jd_id)


@router.delete("/jds/{jd_id}", status_code=204, summary="Delete a job description (Placement Hub moderator or admin)")
async def delete_jd(jd_id: UUID, user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    async with conn.transaction():
        row = await conn.fetchrow("DELETE FROM job_descriptions WHERE id = $1 RETURNING jd_s3_key", jd_id)
        if row is None:
            raise not_found("Job description")
        await log_moderation(conn, user.id, "delete_job_description", "job_description", jd_id)
    if row["jd_s3_key"]:
        await delete_objects([row["jd_s3_key"]])
    return Response(status_code=204)


# ---------------------------------------------------------------- pre-placement talks
async def _ppt_detail(conn: asyncpg.Connection, ppt_id: UUID) -> Ppt:
    r = await conn.fetchrow(_PPT_SELECT + " WHERE p.id = $1", ppt_id)
    if r is None:
        raise not_found("Pre-placement talk")
    return _ppt(r)


@router.get("/placement/ppts", response_model=Page[Ppt],
            summary="The placement schedule across companies: talks, online tests, interviews (signed in only)")
async def list_ppts(when: Literal["upcoming", "past", "all"] = Query(
                        "upcoming", description="upcoming: soonest first; past: latest first"),
                    kind: list[PptKind] | None = Query(None, description="Only these kinds (repeat for several)"),
                    page: PageParams = Depends(page_params), user: CurrentUser = Depends(current_user),
                    conn: asyncpg.Connection = Depends(get_conn)):
    where, order = {
        "upcoming": ("p.scheduled_at >= now()", "p.scheduled_at ASC"),
        "past": ("p.scheduled_at < now()", "p.scheduled_at DESC"),
        "all": ("true", "p.scheduled_at DESC NULLS FIRST"),
    }[when]
    rows = await conn.fetch(
        _PPT_SELECT + f" WHERE {where} AND ($3::text[] IS NULL OR p.kind = ANY($3::text[])) "
                      f"ORDER BY {order}, p.id LIMIT $1 OFFSET $2",
        page.limit + 1, page.offset, kind or None)
    return make_page(rows, page, _ppt)


@router.post("/companies/{company_id}/ppts", response_model=Ppt, status_code=201,
             summary="Add pre-placement talk info (Placement Hub moderator or admin)")
async def create_ppt(company_id: UUID, body: PptIn, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    await _company_exists(conn, company_id)
    if not (body.details or body.venue or body.scheduled_at):
        raise HTTPException(422, "Give at least the details, venue or time.")
    ppt_id = await conn.fetchval(
        """INSERT INTO ppt_info (company_id, kind, details, venue, scheduled_at)
           VALUES ($1, $2, $3, $4, $5) RETURNING id""",
        company_id, body.kind, body.details or None, body.venue or None, body.scheduled_at)
    return await _ppt_detail(conn, ppt_id)


@router.patch("/ppts/{ppt_id}", response_model=Ppt, summary="Edit pre-placement talk info (Placement Hub moderator or admin)")
async def update_ppt(ppt_id: UUID, body: PptUpdate, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM ppt_info WHERE id = $1)", ppt_id):
        raise not_found("Pre-placement talk")
    changes = {k: (v or None) if isinstance(v, str) else v for k, v in body.model_dump(exclude_unset=True).items()}
    if "kind" in changes and changes["kind"] is None:
        raise HTTPException(422, "kind can't be empty.")
    if "scheduled_at" in changes:
        changes["time_tbd"] = False   # a moderator picking the time makes it exact
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        await conn.execute(f"UPDATE ppt_info SET {sql} WHERE id = $1", ppt_id, *values)
        await log_moderation(conn, user.id, "edit_ppt", "ppt", ppt_id)
    return await _ppt_detail(conn, ppt_id)


@router.delete("/ppts/{ppt_id}", status_code=204, summary="Delete pre-placement talk info (Placement Hub moderator or admin)")
async def delete_ppt(ppt_id: UUID, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    async with conn.transaction():
        if not await conn.fetchval("DELETE FROM ppt_info WHERE id = $1 RETURNING true", ppt_id):
            raise not_found("Pre-placement talk")
        await log_moderation(conn, user.id, "delete_ppt", "ppt", ppt_id)
    return Response(status_code=204)


# ---------------------------------------------------------------- hiring statistics (totals only)
@router.get("/companies/{company_id}/hiring-stats", response_model=HiringStats,
            summary="Students selected per year and role (FR-15); never individual students; signed in only")
async def company_hiring_stats(company_id: UUID, user: CurrentUser = Depends(current_user),
                               conn: asyncpg.Connection = Depends(get_conn)):
    name = await conn.fetchval("SELECT name FROM companies WHERE id = $1", company_id)
    if name is None:
        raise not_found("Company")
    rows = await conn.fetch(
        """SELECT placement_year, role_title, students_selected FROM hiring_stats WHERE company_id = $1
           ORDER BY placement_year DESC, students_selected DESC, role_title""", company_id)
    years: dict[int, YearStats] = {}
    for r in rows:
        y = years.setdefault(r["placement_year"], YearStats(year=r["placement_year"], students_selected=0, roles=[]))
        y.students_selected += r["students_selected"]
        y.roles.append(RoleCount(role_title=r["role_title"], students_selected=r["students_selected"]))
    return HiringStats(company_id=company_id, company_name=name, years=list(years.values()),
                       total_selected=sum(y.students_selected for y in years.values()))


@router.get("/placement/stats", response_model=PlacementOverview,
            summary="Placement seasons at a glance (guests: season totals only; signed in: top recruiters too)")
async def placement_overview(years: int = Query(5, ge=1, le=30, description="How many recent seasons"),
                             year: int | None = Query(None, ge=2000, le=2100,
                                                      description="Season for top_companies (default: latest)"),
                             top: int = Query(10, ge=1, le=50),
                             viewer: CurrentUser | None = Depends(optional_user),
                             conn: asyncpg.Connection = Depends(get_conn)):
    seasons = await conn.fetch(
        """SELECT placement_year AS year, count(*) AS students_selected, count(DISTINCT company_id) AS companies
           FROM placement_records GROUP BY placement_year ORDER BY placement_year DESC LIMIT $1""", years)
    season = year if year is not None else (seasons[0]["year"] if seasons else None)
    # Company names, per-company hire counts and pay are the "detailed records" guests sign in to see;
    # season totals above are the free summary.
    top_rows = [] if season is None or viewer is None else await conn.fetch(
        """SELECT c.id AS company_id, c.name AS company_name, count(*) AS students_selected,
                  (SELECT min(j.ctc_min) FROM job_descriptions j WHERE j.company_id = c.id AND j.placement_year = $1
                     AND j.job_type <> 'internship') AS ctc_min,
                  (SELECT max(j.ctc_max) FROM job_descriptions j WHERE j.company_id = c.id AND j.placement_year = $1
                     AND j.job_type <> 'internship') AS ctc_max
           FROM placement_records r JOIN companies c ON c.id = r.company_id
           WHERE r.placement_year = $1
           GROUP BY c.id, c.name ORDER BY students_selected DESC, lower(c.name) LIMIT $2""", season, top)
    pay_year = None if viewer is None else await conn.fetchval(
        "SELECT max(placement_year) FROM job_descriptions WHERE ctc_min IS NOT NULL AND job_type <> 'internship'")
    paying = [] if pay_year is None else await conn.fetch(
        """SELECT c.id AS company_id, c.name AS company_name, min(j.ctc_min) AS ctc_min, max(j.ctc_max) AS ctc_max,
                  count(*) AS roles
           FROM job_descriptions j JOIN companies c ON c.id = j.company_id
           WHERE j.placement_year = $1 AND j.ctc_min IS NOT NULL AND j.job_type <> 'internship'
           GROUP BY c.id, c.name ORDER BY max(j.ctc_max) DESC, lower(c.name) LIMIT $2""", pay_year, top)
    return PlacementOverview(seasons=[SeasonStats(**dict(s)) for s in seasons], year=season,
                             top_companies=[TopCompany(**dict(t)) for t in top_rows], pay_year=pay_year,
                             top_paying=[CompanyPay(**dict(p)) for p in paying])


# ---------------------------------------------------------------- interview experiences
_INTERVIEW_SELECT = """
SELECT i.id, i.company_id, c.name AS company_name, i.role_title, i.placement_year, i.content, i.is_anonymous,
       i.created_at, i.updated_at, i.author_id, u.name AS author_name
FROM interview_experiences i
JOIN companies c ON c.id = i.company_id
JOIN users u ON u.id = i.author_id
"""


def _interview(r: asyncpg.Record, viewer: CurrentUser | None) -> Interview:
    """Names are shown only to signed-in viewers, and never for anonymous posts (except to the author)."""
    mine = viewer is not None and r["author_id"] == viewer.id
    show_name = mine or (viewer is not None and not r["is_anonymous"])
    return Interview(id=r["id"], company_id=r["company_id"], company_name=r["company_name"],
                     role_title=r["role_title"], placement_year=r["placement_year"], content=r["content"],
                     is_anonymous=r["is_anonymous"], is_mine=mine,
                     author=UserRef(id=r["author_id"], name=r["author_name"]) if show_name else None,
                     created_at=r["created_at"], updated_at=r["updated_at"])


async def _interview_detail(conn: asyncpg.Connection, interview_id: UUID, viewer: CurrentUser | None) -> Interview:
    r = await conn.fetchrow(_INTERVIEW_SELECT + " WHERE i.id = $1 AND i.deleted_at IS NULL", interview_id)
    if r is None:
        raise not_found("Interview experience")
    return _interview(r, viewer)


@router.get("/interviews", response_model=Page[Interview],
            summary="Interview experiences, newest first (FR-16; guests allowed)")
async def list_interviews(
    company_id: UUID | None = None,
    q: str | None = Query(None, max_length=200, description="Words in the role or the write-up"),
    role: str | None = Query(None, max_length=200, description="Exact role title, any case"),
    placement_year: int | None = Query(None, ge=2000, le=2100),
    mine: bool = Query(False, description="Only my own posts (signed in)"),
    page: PageParams = Depends(page_params),
    viewer: CurrentUser | None = Depends(optional_user),
    conn: asyncpg.Connection = Depends(get_conn),
):
    if mine and viewer is None:
        raise HTTPException(401, "Sign in to see your own posts.")
    q = search_text(q)
    rows = await conn.fetch(
        _INTERVIEW_SELECT + """
        WHERE i.deleted_at IS NULL
          AND ($1::uuid IS NULL OR i.company_id = $1)
          AND ($2::text IS NULL OR i.content ILIKE '%' || $2 || '%' ESCAPE '\\'
                                OR i.role_title ILIKE '%' || $2 || '%' ESCAPE '\\')
          AND ($3::text IS NULL OR lower(i.role_title) = lower($3))
          AND ($4::int IS NULL OR i.placement_year = $4)
          AND ($5::uuid IS NULL OR i.author_id = $5)
        ORDER BY i.created_at DESC, i.id DESC LIMIT $6 OFFSET $7""",
        company_id, like_pattern(q) if q else None, search_text(role), placement_year,
        viewer.id if mine else None, page.limit + 1, page.offset)
    return make_page(rows, page, lambda r: _interview(r, viewer))


@router.get("/interviews/{interview_id}", response_model=Interview, summary="One interview experience")
async def get_interview(interview_id: UUID, viewer: CurrentUser | None = Depends(optional_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    return await _interview_detail(conn, interview_id, viewer)


@router.post("/companies/{company_id}/interviews", response_model=Interview, status_code=201,
             summary="Share an interview experience (FR-16)")
async def create_interview(company_id: UUID, body: InterviewCreate, user: CurrentUser = Depends(current_user),
                           conn: asyncpg.Connection = Depends(get_conn)):
    await _company_exists(conn, company_id)
    interview_id = await conn.fetchval(
        """INSERT INTO interview_experiences (company_id, author_id, role_title, placement_year, content, is_anonymous)
           VALUES ($1, $2, $3, $4, $5, $6) RETURNING id""",
        company_id, user.id, body.role_title, body.placement_year, body.content, body.is_anonymous)
    return await _interview_detail(conn, interview_id, user)


@router.patch("/interviews/{interview_id}", response_model=Interview,
              summary="Edit an interview experience (author, or admin except the anonymous flag)")
async def update_interview(interview_id: UUID, body: InterviewUpdate, user: CurrentUser = Depends(current_user),
                           conn: asyncpg.Connection = Depends(get_conn)):
    author_id = await conn.fetchval(
        "SELECT author_id FROM interview_experiences WHERE id = $1 AND deleted_at IS NULL", interview_id)
    if author_id is None:
        raise not_found("Interview experience")
    is_author = author_id == user.id
    if not is_author and not user.is_admin:
        raise forbidden("Only the author can edit this post.")
    changes = body.model_dump(exclude_unset=True)
    if any(changes.get(k, 0) is None for k in ("role_title", "content", "is_anonymous")):
        raise HTTPException(422, "role_title, content and is_anonymous can't be empty.")
    if "is_anonymous" in changes and not is_author:
        raise forbidden("Only the author can change whether their name is shown.")
    sql, values = set_clause(changes, start=2)
    async with conn.transaction():
        await conn.execute(f"UPDATE interview_experiences SET {sql} WHERE id = $1", interview_id, *values)
        if not is_author:
            await log_moderation(conn, user.id, "edit_interview_experience", "interview_experience", interview_id)
    return await _interview_detail(conn, interview_id, user)


@router.delete("/interviews/{interview_id}", status_code=204,
               summary="Remove an interview experience (author, Placement Hub moderator or admin)")
async def delete_interview(interview_id: UUID, reason: str | None = Query(None, max_length=500),
                           user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    author_id = await conn.fetchval(
        "SELECT author_id FROM interview_experiences WHERE id = $1 AND deleted_at IS NULL", interview_id)
    if author_id is None:
        raise not_found("Interview experience")
    is_author = author_id == user.id
    if not is_author and not await is_module_moderator(conn, user, MODULE):
        raise forbidden("Only the author or a Placement Hub moderator can remove this post.")
    async with conn.transaction():
        await conn.execute("UPDATE interview_experiences SET deleted_at = now(), deleted_by = $2 WHERE id = $1",
                           interview_id, user.id)
        await close_reports(conn, "interview_experience", [interview_id], user.id, reason)
        if not is_author:
            await log_moderation(conn, user.id, "remove_interview_experience", "interview_experience",
                                 interview_id, reason)
    return Response(status_code=204)


# ---------------------------------------------------------------- bulk import (FR-17)
@router.post("/placement/imports", response_model=ImportResult, status_code=201,
             summary="Import a placement sheet (Placement Hub moderator or admin)")
async def import_sheet(body: ImportRequest, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    """Each well-formed row creates a record, or updates the student's record for that year (re-importing an
    edited sheet doesn't duplicate anyone). Companies not seen before are created. Malformed rows are rejected
    and listed with their line number; they never stop the good rows from importing."""
    await _require_moderator(conn, user)
    try:
        rows, rejected = parse_sheet(body.sheet)
    except SheetError as exc:
        raise HTTPException(422, str(exc)) from exc

    source_key = f"placement-imports/{user.id}/{body.placement_year}-{uuid.uuid4()}.csv"
    try:
        await put_object(source_key, body.sheet.encode(), "text/csv; charset=utf-8")
    except (BotoCoreError, ClientError) as exc:
        # The sheet is kept as the import's source (FR-17 audit trail), so don't import without it.
        raise HTTPException(503, "File storage is unavailable, so the sheet couldn't be saved. Nothing was "
                                 "imported; try again shortly.") from exc
    created = updated = 0
    new_companies: list[str] = []
    company_ids: dict[str, UUID] = {}
    async with conn.transaction():
        import_id, imported_at = await conn.fetchrow(
            """INSERT INTO placement_bulk_imports (moderator_id, placement_year, source_s3_key, rows_total,
                                                   rows_created, rows_updated, rows_rejected)
               VALUES ($1, $2, $3, 0, 0, 0, 0) RETURNING id, imported_at""",
            user.id, body.placement_year, source_key)
        for row in rows:
            key = row.company.lower()
            if key not in company_ids:
                company = await conn.fetchrow(
                    """INSERT INTO companies (name, created_by) VALUES ($1, $2)
                       ON CONFLICT (name_key) DO UPDATE SET name = companies.name
                       RETURNING id, (xmax = 0) AS was_created""", row.company, user.id)
                company_ids[key] = company["id"]
                if company["was_created"]:
                    new_companies.append(row.company)
            was_created = await conn.fetchval(
                """INSERT INTO placement_records (import_id, placement_year, slot, company_id, role_title, student_email)
                   VALUES ($1, $2, $3, $4, $5, $6)
                   ON CONFLICT (placement_year, student_email) DO UPDATE
                     SET slot = EXCLUDED.slot, company_id = EXCLUDED.company_id,
                         role_title = EXCLUDED.role_title, import_id = EXCLUDED.import_id
                   RETURNING (xmax = 0)""",
                import_id, body.placement_year, row.slot, company_ids[key], row.role, row.email)
            if was_created:
                created += 1
            else:
                updated += 1
        await conn.execute(
            """UPDATE placement_bulk_imports SET rows_total = $2, rows_created = $3, rows_updated = $4,
                      rows_rejected = $5 WHERE id = $1""",
            import_id, created + updated + len(rejected), created, updated, len(rejected))
        await log_moderation(conn, user.id, "import_placement_sheet", "placement_bulk_import", import_id,
                             f"{body.placement_year}: {created} created, {updated} updated, {len(rejected)} rejected")
    return ImportResult(id=import_id, placement_year=body.placement_year, rows_total=created + updated + len(rejected),
                        rows_created=created, rows_updated=updated, rows_rejected=len(rejected),
                        companies_created=new_companies,
                        rejected_rows=[RejectedRowOut(line=r.line, reason=r.reason) for r in rejected],
                        imported_at=imported_at,
                        similar_companies=await _similar_groups(conn, set(company_ids.values())))


@router.get("/placement/imports", response_model=Page[ImportSummary],
            summary="Past placement sheet imports (Placement Hub moderator or admin)")
async def list_imports(page: PageParams = Depends(page_params), user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    rows = await conn.fetch(
        """SELECT b.id, b.placement_year, b.rows_total, b.rows_created, b.rows_updated, b.rows_rejected,
                  b.imported_at, b.moderator_id, u.name AS moderator_name
           FROM placement_bulk_imports b JOIN users u ON u.id = b.moderator_id
           ORDER BY b.imported_at DESC, b.id DESC LIMIT $1 OFFSET $2""", page.limit + 1, page.offset)
    return make_page(rows, page, lambda r: ImportSummary(
        id=r["id"], placement_year=r["placement_year"], rows_total=r["rows_total"], rows_created=r["rows_created"],
        rows_updated=r["rows_updated"], rows_rejected=r["rows_rejected"], imported_at=r["imported_at"],
        moderator=UserRef(id=r["moderator_id"], name=r["moderator_name"])))


# ---------------------------------------------------------------- CSV imports: companies and schedule
async def _company_id_for(conn: asyncpg.Connection, name: str, created: list[str], creator: UUID) -> UUID:
    """The company called [name], added (by [creator]) if it doesn't exist yet."""
    row = await conn.fetchrow(
        """INSERT INTO companies (name, created_by) VALUES ($1, $2)
           ON CONFLICT (name_key) DO UPDATE SET name = companies.name
           RETURNING id, (xmax = 0) AS was_created""", name, creator)
    if row["was_created"]:
        created.append(name)
    return row["id"]


@router.post("/placement/companies/import", response_model=CsvImportResult, status_code=201,
             summary="Add or update companies from a CSV (Placement Hub moderator or admin)")
async def import_companies(body: CsvImportRequest, user: CurrentUser = Depends(current_user),
                           conn: asyncpg.Connection = Depends(get_conn)):
    """Columns: Name (required), Industry, Website, About. A company that already exists (same name, any
    case) is updated with the non-empty cells; the rest are created."""
    await _require_moderator(conn, user)
    try:
        rows, rejected = parse_companies(body.csv)
    except SheetError as exc:
        raise HTTPException(422, str(exc)) from exc
    created: list[str] = []
    updated = 0
    async with conn.transaction():
        for row in rows:
            was_created = await conn.fetchval(
                """INSERT INTO companies (name, industry, website, description, created_by) VALUES ($1, $2, $3, $4, $5)
                   ON CONFLICT (name_key) DO UPDATE
                     SET industry = coalesce(EXCLUDED.industry, companies.industry),
                         website = coalesce(EXCLUDED.website, companies.website),
                         description = coalesce(EXCLUDED.description, companies.description)
                   RETURNING (xmax = 0)""", row.name, row.industry, row.website, row.description, user.id)
            if was_created:
                created.append(row.name)
            else:
                updated += 1
        await log_moderation(conn, user.id, "import_companies", "placement_csv", user.id,
                             f"{len(created)} created, {updated} updated, {len(rejected)} rejected")
    return CsvImportResult(rows_total=len(rows) + len(rejected), rows_created=len(created), rows_updated=updated,
                           rows_rejected=len(rejected), companies_created=created,
                           rejected_rows=[RejectedRowOut(line=r.line, reason=r.reason) for r in rejected])


@router.post("/placement/schedule/import", response_model=CsvImportResult, status_code=201,
             summary="Add placement dates (talks, online tests, interviews) from a CSV (Placement Hub moderator or admin)")
async def import_schedule(body: CsvImportRequest, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    """Columns: Company (required), Type (PPT, OA, Interview or Other; else from the column names or the file
    name, e.g. "Venue of Interview" or "slot 2 test schedule.csv"; default PPT), Date and Time (or one
    Date and time column; India time unless a timezone is given), Venue, Details. Companies not seen before
    are created. A row with the same company, type and time as an existing entry updates its venue and
    details instead of adding it twice."""
    await _require_moderator(conn, user)
    try:
        rows, rejected = parse_schedule(body.csv, body.file_name)
    except SheetError as exc:
        raise HTTPException(422, str(exc)) from exc
    new_companies: list[str] = []
    company_ids: dict[str, UUID] = {}
    created = updated = past = 0
    kinds: dict[str, int] = {}
    now = datetime.now(timezone.utc)
    async with conn.transaction():
        for row in rows:
            key = row.company.lower()
            if key not in company_ids:
                company_ids[key] = await _company_id_for(conn, row.company, new_companies, user.id)
            existing = None
            if row.scheduled_at is not None:
                existing = await conn.fetchval(
                    "SELECT id FROM ppt_info WHERE company_id = $1 AND kind = $2 AND scheduled_at = $3",
                    company_ids[key], row.kind, row.scheduled_at)
            if existing:
                await conn.execute(
                    """UPDATE ppt_info SET venue = coalesce($2, venue), details = coalesce($3, details), time_tbd = $4
                       WHERE id = $1""", existing, row.venue, row.details, row.time_tbd)
                updated += 1
            else:
                await conn.execute(
                    """INSERT INTO ppt_info (company_id, kind, details, venue, scheduled_at, time_tbd)
                       VALUES ($1, $2, $3, $4, $5, $6)""",
                    company_ids[key], row.kind, row.details, row.venue, row.scheduled_at, row.time_tbd)
                created += 1
            kinds[row.kind] = kinds.get(row.kind, 0) + 1
            if row.scheduled_at is not None and row.scheduled_at < now:
                past += 1
        await log_moderation(conn, user.id, "import_schedule", "placement_csv", user.id,
                             f"{created} created, {updated} updated, {len(rejected)} rejected")
    return CsvImportResult(rows_total=len(rows) + len(rejected), rows_created=created, rows_updated=updated,
                           rows_rejected=len(rejected), companies_created=new_companies,
                           rejected_rows=[RejectedRowOut(line=r.line, reason=r.reason) for r in rejected],
                           kinds=kinds, past_rows=past)


# ---------------------------------------------------------------- seniors to contact (rev 18)
SENIOR_SEASONS = 2
OfferType = Literal["on_campus", "off_campus", "ppo", "internship"]


class SeniorIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: str = Field(min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    phone: str | None = Field(None, pattern=r"^\+?[0-9]{10,15}$")
    role_title: str | None = Field(None, max_length=200)
    placement_year: int = Field(ge=2000, le=2100)
    offer_type: OfferType = "off_campus"
    note: str | None = Field(None, max_length=500)

    @field_validator("name", "role_title", "note", mode="before")
    @classmethod
    def _strip(cls, v):
        return v.strip() or None if isinstance(v, str) else v


class SeniorUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=120)
    email: str | None = Field(None, min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    phone: str | None = Field(None, pattern=r"^\+?[0-9]{10,15}$")
    role_title: str | None = Field(None, max_length=200)
    placement_year: int | None = Field(None, ge=2000, le=2100)
    offer_type: OfferType | None = None
    note: str | None = Field(None, max_length=500)


class Senior(BaseModel):
    id: UUID
    source: Literal["placement_sheet", "added"] = Field(
        description="placement_sheet: a student from an imported placement sheet; added: added by a moderator")
    name: str
    email: str
    phone: str | None = Field(None, description="Their phone, if they gave one")
    user_id: UUID | None = Field(None, description="Their CampusHub account, if they have one (needed to chat)")
    role_title: str | None
    placement_year: int
    offer_type: OfferType
    slot: str | None = None
    note: str | None = None
    hidden: bool = Field(False, description="Taken off the list by a moderator (only moderators see these)")


class HiddenIn(BaseModel):
    hidden: bool


def _name_from_email(email: str) -> str:
    return email.split("@", 1)[0]


@router.get("/companies/{company_id}/seniors", response_model=list[Senior],
            summary="Seniors who got an offer here in the last two seasons, to contact (signed-in users)")
async def list_seniors(company_id: UUID, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    """Students (IISc addresses) from the imported placement sheets of the last two seasons, plus seniors Placement Hub moderators
    added (off-campus offers, PPOs, alumni). Their CampusHub name and phone are used when they have an account.
    Guests can't see anyone; moderators also see rows they hid."""
    await _company_exists(conn, company_id)
    moderator = await is_module_moderator(conn, user, MODULE)
    rows = await conn.fetch(
        """SELECT * FROM (
             SELECT r.id, 'placement_sheet' AS source, u.name AS account_name, NULL::text AS given_name,
                    r.student_email::text AS email, u.phone, u.id AS user_id, r.role_title, r.placement_year,
                    CASE WHEN r.slot ILIKE 'ppo%' THEN 'ppo' ELSE 'on_campus' END AS offer_type, r.slot,
                    NULL::text AS note, r.contact_hidden AS hidden
             FROM placement_records r LEFT JOIN users u ON lower(u.email::text) = lower(r.student_email::text)
             WHERE r.company_id = $1 AND r.student_email ~* '@([a-z0-9-]+\\.)*iisc\\.ac\\.in$'   -- IISc people only
             UNION ALL
             SELECT s.id, 'added', u.name, s.name, s.email, coalesce(s.phone, u.phone), u.id, s.role_title,
                    s.placement_year, s.offer_type, NULL, s.note, false
             FROM company_seniors s LEFT JOIN users u ON lower(u.email::text) = lower(s.email)
             WHERE s.company_id = $1) x
           WHERE x.placement_year >= (SELECT max(placement_year) FROM (
                     SELECT placement_year FROM placement_records WHERE company_id = $1
                     UNION ALL SELECT placement_year FROM company_seniors WHERE company_id = $1
                     UNION ALL SELECT extract(year FROM now() AT TIME ZONE 'Asia/Kolkata')::int - 1) y) - $2 + 1
             AND ($3 OR NOT x.hidden)
           ORDER BY x.placement_year DESC, x.hidden, (x.user_id IS NULL), coalesce(x.given_name, x.account_name, x.email)""",
        company_id, SENIOR_SEASONS, moderator)
    return [Senior(id=r["id"], source=r["source"], name=r["given_name"] or r["account_name"] or _name_from_email(r["email"]),
                   email=r["email"], phone=r["phone"], user_id=r["user_id"], role_title=r["role_title"],
                   placement_year=r["placement_year"], offer_type=r["offer_type"], slot=r["slot"], note=r["note"],
                   hidden=r["hidden"]) for r in rows]


@router.post("/companies/{company_id}/seniors", response_model=Senior, status_code=201,
             summary="Add a senior to contact, e.g. an off-campus offer (Placement Hub moderator or admin)")
async def add_senior(company_id: UUID, body: SeniorIn, user: CurrentUser = Depends(current_user),
                     conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    await _company_exists(conn, company_id)
    async with conn.transaction():
        try:
            senior_id = await conn.fetchval(
                """INSERT INTO company_seniors (company_id, name, email, phone, role_title, placement_year, offer_type,
                                                note, added_by)
                   VALUES ($1, $2, lower($3), $4, $5, $6, $7, $8, $9) RETURNING id""",
                company_id, body.name, body.email, body.phone, body.role_title, body.placement_year, body.offer_type,
                body.note, user.id)
        except asyncpg.UniqueViolationError as exc:
            raise HTTPException(409, "This senior is already listed for that season.") from exc
        await log_moderation(conn, user.id, "add_company_senior", "company", company_id, body.email)
    return await _senior(conn, senior_id)


async def _senior(conn: asyncpg.Connection, senior_id: UUID) -> Senior:
    r = await conn.fetchrow(
        """SELECT s.*, coalesce(s.phone, u.phone) AS any_phone, u.id AS user_id
           FROM company_seniors s LEFT JOIN users u ON lower(u.email::text) = s.email WHERE s.id = $1""", senior_id)
    if r is None:
        raise not_found("Senior")
    return Senior(id=r["id"], source="added", name=r["name"], email=r["email"], phone=r["any_phone"],
                  user_id=r["user_id"], role_title=r["role_title"], placement_year=r["placement_year"],
                  offer_type=r["offer_type"], note=r["note"])


@router.patch("/seniors/{senior_id}", response_model=Senior,
              summary="Edit a senior a moderator added (Placement Hub moderator or admin)")
async def update_senior(senior_id: UUID, body: SeniorUpdate, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    changes = body.model_dump(exclude_unset=True)
    for required in ("name", "email", "placement_year", "offer_type"):
        if required in changes and changes[required] is None:
            raise HTTPException(422, f"{required} can't be empty.")
    if "email" in changes:
        changes["email"] = changes["email"].lower()
    if changes:
        assignments = ", ".join(f"{k} = ${i}" for i, k in enumerate(changes, start=2))
        async with conn.transaction():
            try:
                found = await conn.fetchval(
                    f"UPDATE company_seniors SET {assignments}, updated_at = now() WHERE id = $1 RETURNING true",
                    senior_id, *changes.values())
            except asyncpg.UniqueViolationError as exc:
                raise HTTPException(409, "This senior is already listed for that season.") from exc
            if not found:
                raise not_found("Senior")
            await log_moderation(conn, user.id, "edit_company_senior", "company_senior", senior_id)
    return await _senior(conn, senior_id)


@router.delete("/seniors/{senior_id}", status_code=204,
               summary="Remove a senior a moderator added (Placement Hub moderator or admin)")
async def delete_senior(senior_id: UUID, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    async with conn.transaction():
        if not await conn.fetchval("DELETE FROM company_seniors WHERE id = $1 RETURNING true", senior_id):
            raise not_found("Senior")
        await log_moderation(conn, user.id, "delete_company_senior", "company_senior", senior_id)
    return Response(status_code=204)


@router.put("/placement/records/{record_id}/contact-hidden", status_code=204,
            summary="Hide or show a placement sheet student in a company's seniors list (Placement Hub moderator)")
async def hide_sheet_senior(record_id: UUID, body: HiddenIn, user: CurrentUser = Depends(current_user),
                            conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    async with conn.transaction():
        if not await conn.fetchval("UPDATE placement_records SET contact_hidden = $2 WHERE id = $1 RETURNING true",
                                   record_id, body.hidden):
            raise not_found("Placement record")
        await log_moderation(conn, user.id, "hide_company_senior" if body.hidden else "show_company_senior",
                             "placement_record", record_id)
    return Response(status_code=204)


# ---------------------------------------------------------------- roles and compensation (rev 21)
class RolesImportRequest(BaseModel):
    csv: str = Field(min_length=1, max_length=5_000_000, description="Rows of a roles-and-compensation file")
    placement_year: int | None = Field(None, ge=2000, le=2100,
                                       description="Season for rows without a Batch/Year column (e.g. 2026 for 2025-26)")


@router.post("/placement/roles/import", response_model=CsvImportResult, status_code=201,
             summary="Import roles and compensation (Placement Hub moderator or admin)")
async def import_roles(body: RolesImportRequest, user: CurrentUser = Depends(current_user),
                       conn: asyncpg.Connection = Depends(get_conn)):
    """Columns by name (app/placement_roles.py): Company and Position / Job title (required); Batch or Year;
    Overall CTC; Base; Job type; Description; Skills. Compensation stays as written and its amount is read into
    rupees a year. A role is one company, title, season and type: importing again updates it, filling in what
    the file has and keeping what it doesn't."""
    await _require_moderator(conn, user)
    try:
        rows, rejected = parse_roles(body.csv, body.placement_year)
    except SheetError as exc:
        raise HTTPException(422, str(exc)) from exc
    new_companies: list[str] = []
    company_ids: dict[str, UUID] = {}
    created = updated = 0
    async with conn.transaction():
        for row in rows:
            key = row.company.lower()
            if key not in company_ids:
                company_ids[key] = await _company_id_for(conn, row.company, new_companies, user.id)
            was_created = await conn.fetchval(
                """INSERT INTO job_descriptions (company_id, role_title, placement_year, job_type, compensation, ctc_min,
                                                 ctc_max, base_text, base_annual, description, skills)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                   ON CONFLICT (company_id, lower(role_title), coalesce(placement_year, 0), job_type) DO UPDATE SET
                     compensation = coalesce(EXCLUDED.compensation, job_descriptions.compensation),
                     ctc_min = coalesce(EXCLUDED.ctc_min, job_descriptions.ctc_min),
                     ctc_max = coalesce(EXCLUDED.ctc_max, job_descriptions.ctc_max),
                     base_text = coalesce(EXCLUDED.base_text, job_descriptions.base_text),
                     base_annual = coalesce(EXCLUDED.base_annual, job_descriptions.base_annual),
                     description = coalesce(EXCLUDED.description, job_descriptions.description),
                     skills = coalesce(EXCLUDED.skills, job_descriptions.skills),
                     updated_at = now()
                   RETURNING (xmax = 0)""",
                company_ids[key], row.role, row.placement_year, row.job_type, row.ctc_text, row.ctc_min, row.ctc_max,
                row.base_text, row.base_annual, row.description, row.skills)
            if was_created:
                created += 1
            else:
                updated += 1
        await log_moderation(conn, user.id, "import_roles", "placement_csv", user.id,
                             f"{created} created, {updated} updated, {len(rejected)} rejected")
    return CsvImportResult(rows_total=len(rows) + len(rejected), rows_created=created, rows_updated=updated,
                           rows_rejected=len(rejected), companies_created=new_companies,
                           rejected_rows=[RejectedRowOut(line=r.line, reason=r.reason) for r in rejected])


# ---------------------------------------------------------------- similar companies and merging them
async def _similar_groups(conn: asyncpg.Connection, touching: set[UUID] | None = None) -> list[SimilarCompanyGroup]:
    """Groups of companies whose names are probably one company (app/company_matching.py). With [touching],
    only the groups that include one of those companies."""
    rows = await conn.fetch(
        """SELECT c.id, c.name, (SELECT count(*) FROM placement_records r WHERE r.company_id = c.id)::int AS records
           FROM companies c ORDER BY records DESC, c.name""")
    by_id = {r["id"]: r for r in rows}
    groups = []
    for ids in group_similar({r["id"]: r["name"] for r in rows}):
        if touching is not None and not touching.intersection(ids):
            continue
        members = [by_id[i] for i in ids]
        groups.append(SimilarCompanyGroup(
            suggested_name=suggested_name([m["name"] for m in members], [m["records"] for m in members]),
            companies=[SimilarCompany(id=m["id"], name=m["name"], records=m["records"]) for m in members]))
    return groups


@router.get("/placement/companies/similar", response_model=list[SimilarCompanyGroup],
            summary="Companies that are probably the same one under different names (Placement Hub moderator or admin)")
async def similar_companies(user: CurrentUser = Depends(current_user), conn: asyncpg.Connection = Depends(get_conn)):
    await _require_moderator(conn, user)
    return await _similar_groups(conn)


@router.post("/placement/companies/merge", response_model=CompanyDetail,
             summary="Merge companies into one under a common name (Placement Hub moderator or admin)")
async def merge_companies(body: CompanyMerge, user: CurrentUser = Depends(current_user),
                          conn: asyncpg.Connection = Depends(get_conn)):
    """Everything under the other companies (placement records, roles, dates, interviews, seniors, forum
    threads) moves to one of them, which takes [name]; the others are deleted. A role or senior that the kept
    company already has (same role and season, or same email and year) is dropped rather than duplicated."""
    await _require_moderator(conn, user)
    ids = list(dict.fromkeys(body.company_ids))
    name = " ".join(body.name.split())
    if len(ids) < 2:
        raise HTTPException(422, "Pick at least two different companies to merge.")
    async with conn.transaction():
        rows = await conn.fetch(
            """SELECT c.id, c.name, c.name_key, (SELECT count(*) FROM placement_records r WHERE r.company_id = c.id) AS n
               FROM companies c WHERE c.id = ANY($1::uuid[]) FOR UPDATE""", ids)
        if len(rows) != len(ids):
            raise not_found("Company")
        clash = await conn.fetchval(
            """SELECT name FROM companies WHERE name_key = lower(regexp_replace(btrim($1), '\\s+', ' ', 'g'))
               AND NOT (id = ANY($2::uuid[]))""", name, ids)
        if clash:
            raise HTTPException(409, f"Another company is already called “{clash}”. Include it in the merge or "
                                     "pick a different name.")
        # Keep the one already called [name], else the one with the most records.
        name_key = " ".join(name.lower().split())
        keep = next((r for r in rows if r["name_key"] == name_key), max(rows, key=lambda r: r["n"]))["id"]
        others = [r["id"] for r in rows if r["id"] != keep]
        for other in others:
            await conn.execute(
                """DELETE FROM job_descriptions j WHERE j.company_id = $1 AND EXISTS (
                       SELECT 1 FROM job_descriptions k WHERE k.company_id = $2 AND lower(k.role_title) = lower(j.role_title)
                       AND coalesce(k.placement_year, 0) = coalesce(j.placement_year, 0) AND k.job_type = j.job_type)""",
                other, keep)
            await conn.execute(
                """DELETE FROM company_seniors s WHERE s.company_id = $1 AND EXISTS (
                       SELECT 1 FROM company_seniors k WHERE k.company_id = $2 AND k.email = s.email
                       AND k.placement_year = s.placement_year)""", other, keep)
            for table in ("job_descriptions", "ppt_info", "interview_experiences", "placement_records",
                          "company_seniors"):
                await conn.execute(f"UPDATE {table} SET company_id = $2 WHERE company_id = $1", other, keep)
            forum = await conn.fetchval("SELECT id FROM forums WHERE company_id = $1", other)
            if forum is not None:
                kept_forum = await conn.fetchval("SELECT id FROM forums WHERE company_id = $1", keep)
                if kept_forum is None:
                    await conn.execute("UPDATE forums SET company_id = $2 WHERE id = $1", forum, keep)
                else:
                    await conn.execute("UPDATE threads SET forum_id = $2 WHERE forum_id = $1", forum, kept_forum)
                    await conn.execute("DELETE FROM forums WHERE id = $1", forum)
        await conn.execute(
            """UPDATE companies k SET
                   description = coalesce(k.description, (SELECT o.description FROM companies o
                                 WHERE o.id = ANY($2::uuid[]) AND o.description IS NOT NULL LIMIT 1)),
                   website = coalesce(k.website, (SELECT o.website FROM companies o
                             WHERE o.id = ANY($2::uuid[]) AND o.website IS NOT NULL LIMIT 1)),
                   industry = coalesce(k.industry, (SELECT o.industry FROM companies o
                              WHERE o.id = ANY($2::uuid[]) AND o.industry IS NOT NULL LIMIT 1))
               WHERE k.id = $1""", keep, others)
        await conn.execute("DELETE FROM companies WHERE id = ANY($1::uuid[])", others)
        await conn.execute("UPDATE companies SET name = $2 WHERE id = $1", keep, name)
        await log_moderation(conn, user.id, "merge_companies", "company", keep,
                             f"{', '.join(r['name'] for r in rows)} -> {name}")
    return await _company_detail(conn, keep, user)
