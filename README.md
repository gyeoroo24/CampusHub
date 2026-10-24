# CampusHub
This repository contains our group project for the course DS252-Introduction to Cloud Computing as a part of masters program at IISc.

CampusHub is one app for IISc students: Buy & Sell, Lost & Found, Academic Help, Placement Hub and
campus events. The backend runs on AWS Lambda (FastAPI), with PostgreSQL on RDS, S3 for files and
Cognito for IISc sign-in.

## What's in this repository

```
backend/                FastAPI backend: code, tests, Docker files, database schema
  db/schema.sql         PostgreSQL schema (revision 5)
docs/
  CampusHub-PRD-v1.pdf  Product requirements document (v1, 30 Sep 2026)
  api-reference.md      Every API endpoint, for frontend design
  schema/               Database diagrams (PNG and SVG), one per module
```

## Status

- **Phase 1 backend is built:** sign-in and profiles, moderator roles, Buy & Sell, Lost & Found,
  Academic Help, forums, reports and moderation, notifications. 71 endpoints, 80 passing tests.
- **Review fixes (24 Oct 2026):** the bugs from the 23 Oct backend review are fixed and covered
  by `backend/tests/test_review_fixes.py`.
- **Not built yet:** Placement Hub and Events APIs, real push delivery, chat, Terraform, frontend.

## Run the backend locally

Needs Docker and Python 3.12. Full steps are in [backend/README.md](backend/README.md); in short:

```bash
cd backend
docker compose up -d
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.local.example .env
uvicorn app.main:app --reload --env-file .env
```

Then open http://localhost:8000/docs.
