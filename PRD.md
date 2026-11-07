# CampusHub: An IISc Student Community Platform

**Project Requirements Document — v2 (As Built)**

DS252 Introduction to Cloud Computing, PRD of Order of Phoenix

> This is a rewrite of the project plan, describing our web app called CampusHub. For the original plan, see
> [`Cloud_Computing_Project-PRD.pdf`](Cloud_Computing_Project-PRD.pdf) (v1, 24 October 2026). 

| | |
|---|---|
| **Team name** | Order of Phoenix |
| **Team members** | Mohammad Sufyan Azam (SR 26898, mohammadazam@iisc.ac.in)<br>Adithya Chippa (SR 26643, cadithya@iisc.ac.in)<br>Lakhani Dinky Ashokbhai (SR 26648, dinkylakhani@iisc.ac.in)<br>Mukund Kukreja (SR 25862, kmukund@iisc.ac.in) |
| **Summary** | A cross-platform IISc community web app unifying Buy & Sell, Lost & Found, Academic Help, Placement Hub, Community Events, mess menus, forums and messaging — deployed twice on AWS (serverless and EC2) for a head-to-head architecture comparison. |
| **Date** | 7 November 2026 |
| **Version** | v2 (as built) |

## Table of contents

1. [Problem statement and motivation](#1-problem-statement-and-motivation)
2. [What was built](#2-what-was-built)
3. [Roles and permissions](#3-roles-and-permissions)
4. [Module-by-module capabilities](#4-module-by-module-capabilities)
5. [Beyond the original plan](#5-beyond-the-original-plan)
6. [System architecture and technology stack](#6-system-architecture-and-technology-stack)
7. [Security and data protection](#7-security-and-data-protection)
8. [Evaluation: serverless vs. EC2](#8-evaluation-serverless-vs-ec2)
9. [Testing](#9-testing)
10. [Team](#10-team)

## 1. Problem statement and motivation

IISc's roughly 6,000 students ran the functions of a campus community platform through ad hoc channels:
second-hand Buy & Sell and Lost & Found over WhatsApp groups that scroll out of relevance within days; course
and exam-preparation knowledge passed down informally between batches; and placement and interview material
scattered across personal notes and one-off senior–junior conversations. None of it was searchable, persistent
or structured, so each cohort rebuilt this institutional knowledge from scratch.

CampusHub replaces those ad hoc channels with a single, persistent, filterable, campus-scoped application:
a web app that any verified IISc student can rely on throughout their programme, backed by cloud
infrastructure chosen specifically because campus traffic is bursty and calendar-driven (Buy & Sell spikes at
semester boundaries, Placement Hub spikes during interview season) and because the data itself — thousands of
listings, reports, reviews and placement records — must stay durable and queryable across years of cohorts.

## 2. What was built

CampusHub is a single Flutter web application and FastAPI backend, deployed **twice** on AWS from the same
codebase so the two deployments could be measured against each other:

- **Serverless**: CloudFront → API Gateway → 5 AWS Lambda functions → RDS PostgreSQL + ElastiCache Redis.
- **EC2 baseline**: CloudFront → Application Load Balancer → EC2 Auto Scaling group → the same RDS and Redis.

Both are fully provisioned by Terraform, both run the identical application code, and both were load-tested
with Locust to produce the architecture comparison described in [section 8](#8-evaluation-serverless-vs-ec2).

Eight product areas are live on both deployments:

| Module | What it does |
|---|---|
| **Buy & Sell** | Second-hand listings with photos, price, category and location; status tracking (Available / Reserved / Sold); search and filter; price-drop watch; seller trust and moderation |
| **Wanted** | "Looking for" posts that alert the poster when a matching listing appears |
| **Lost & Found** | Separate lost/found report flows with automatic photo- and description-based match suggestions |
| **Academic Help** | Departments → courses, course feedback with sentiment analysis, shared materials, a one-page course survival guide, and course discussion forums |
| **Placement Hub** | Company pages (JD, pre-placement-talk info, multi-year hiring statistics, interview experiences, senior contacts), company forums, and bulk CSV import of historical placement records |
| **Community Events** | A tag-filtered events timeline that auto-classifies Past / Present / Upcoming, with bookmarking and tag-follow alerts |
| **Mess** | Daily mess menus (read from PDFs/photos by OCR) with follow-and-alert on meal updates |
| **Messages** | One-to-one chat per pair of users, including offers that reserve a Buy & Sell listing |

All eight sit behind one IISc-email sign-in (Cognito), one four-role permission model enforced independently
per module, one notifications inbox, and one admin panel.

## 3. Roles and permissions

CampusHub enforces four roles, checked on every request directly from the database (never from token claims),
so a revoked moderator loses access on their very next call:

1. **Guest** (not signed in) — reads every public feed: listings, Lost & Found, courses, placement pages,
   events, mess menus. Bookmarks are kept in the browser and moved to the account at sign-in.
2. **Signed-in user** — everything a guest can do, plus creating, editing and deleting their own posts,
   feedback, forum threads and profile; messaging other users; bookmarking, following and saving searches.
3. **Moderator** — scoped by the admin to one module (Buy & Sell, Lost & Found, Placement Hub, Events) or, for
   Academic Help, to a department or a single course. Department-level Academic Help moderators additionally
   manage courses, materials and course-level moderators. Moderators remove posts in their scope and work the
   reports queue.
4. **Administrator** — exactly one account at a time. Everything above, plus granting and revoking moderators,
   deactivating accounts, editing landing-page campus services, and handing the admin role to someone else.

## 4. Module-by-module capabilities

### 4.1 Buy & Sell

Students post listings with title, description, price, category, location and photos; the system suggests a
category from the title text. Owners move a listing through Available → Reserved → Sold. Listings are
searchable and filterable by category, price range and keyword. Buyers can watch a listing for price drops and
see a "Negotiable" signal. Every listing carries a seller trust signal, driven only by moderator-confirmed
removals (strikes, with an appeal/unblock-request flow) — never by an automated judgment. New posts are
automatically screened (keywords, gibberish/spam detection, an image check) and flagged for a human moderator;
nothing is auto-removed without one. A companion **Wanted** board lets a student post what they're looking for
and get alerted when a matching listing appears.

### 4.2 Lost & Found

Students file a lost or a found report (description, category, date, location, optional photo). A matching
engine scores lost/found pairs by text and photo similarity (small ONNX embedding models), surfaces likely
matches, and notifies the original reporter. Where the embedding models aren't available (for example, the
trimmed Lambda deployment), the system falls back to a same-category match rule rather than failing.

### 4.3 Academic Help

Students browse departments and courses; a course with no content yet returns an explicit "no data" state
rather than an error or a blank page. Students post text course feedback, which is scored for sentiment and
summarized into a one-page **course survival guide**. Department-level moderators (often appointed TAs or
students who took the course) upload and curate materials — notes, slides, past assignments; department
moderators have full CRUD over their department's courses and materials and appoint course-level moderators,
who in turn manage only their own course's material. Students can follow a course to be told about new
materials, feedback and forum posts, and discuss in a course forum.

### 4.4 Placement Hub

Company pages show the job description, pre-placement-talk information, aggregated multi-year hiring
statistics, interview experiences submitted by students, and contact details for seniors at that company, plus
a company discussion forum. Placement Hub moderators bulk-import historical placement records, company lists
and interview schedules from CSV exports of spreadsheets; malformed rows are rejected and reported back, never
silently dropped.

### 4.5 Community Events

Events are browsable by category/tag (Sports, Food/Mess, Nature, Photography, Culture, …) and each one
auto-classifies itself as Past, Present or Upcoming purely from its start/end time. Students bookmark
individual events or follow a tag, and are notified when a bookmarked event or a followed tag's event updates.

### 4.6 Mess

Daily menus per campus mess, extracted automatically from a PDF or photo of the posted menu using OCR, with a
follow option that sends a meal alert to subscribers.

### 4.7 Messages

Each pair of signed-in users has exactly one conversation. Buy & Sell sellers and buyers can message directly
from a listing, and a seller can send an offer that, on acceptance, reserves the listing. Messages are
encrypted with server-held keys.

### 4.8 Notifications

One inbox collects every alert the platform generates — Lost & Found matches, forum replies, listing-status
and price-watch updates, bookmarked-event updates, mess alerts, saved-search hits and chat messages — with
in-app delivery for everyone and Web Push to browsers that opt in.

### 4.9 Administration

The admin panel grants and revokes moderator roles (scoped to a module, department or course), reviews a
cross-module reports queue, handles Buy & Sell seller strikes/appeals/unblock requests, runs Placement Hub
imports, and edits the campus-services links used across the app.

## 5. Beyond the original plan

A number of capabilities were built that were not in the v1 scope, because they turned out to make the core
modules materially more useful:

- **Wanted posts** — a request-side companion to Buy & Sell, with alerts when a match is listed.
- **Seller trust and moderation** — trust scores and tags driven only by confirmed moderator action, plus a
  seller appeal/unblock-request flow.
- **Automatic content screening** — keyword, gibberish/spam and image checks that flag new posts for a human
  moderator (content is never auto-removed by the model).
- **Price watch** — price-drop alerts and a "Negotiable" signal on Buy & Sell listings.
- **Smarter category suggestion** — a listing's category is suggested from its title text.
- **Saved searches** — persistent search filters that alert the user when a new match appears.
- **Course survival guide** — a one-page, sentiment-scored summary of a course's accumulated feedback.
- **Lost & Found photo + description matching** — ONNX embedding models score candidate matches instead of a
  plain category match.
- **Mess menus** — OCR-extracted daily menus with meal-alert subscriptions.
- **One-to-one messaging** — direct chat, including listing-reservation offers, server-side encrypted.
- **Forums** — course, department and company discussion threads with upvotes/downvotes.
- **A second, independently deployed EC2 baseline stack** — the same application built and measured against
  the serverless deployment, to produce the architecture comparison in [section 8](#8-evaluation-serverless-vs-ec2).
- **An ElastiCache Redis cache and CloudFront edge caching** in front of the most-read list endpoints, with a
  viewer-aware cache key so no user is ever served another user's cached response.

## 6. System architecture and technology stack

### 6.1 Serverless deployment (primary)

```
Users → Route 53 / CloudFront (CDN, edge cache on list endpoints) → S3 (Flutter web bundle)
                                   │
                                   ├─→ API Gateway (HTTP API) → 5 Lambda functions (FastAPI via Mangum)
                                   │        buy-sell · lost-found · placement-hub · academic-hub · community-events
                                   │        running in private subnets across 3 Availability Zones
                                   │
                        ElastiCache Redis (read cache)      RDS PostgreSQL 16 (system of record)
                                   │
                          Cognito (IISc-email sign-in, Hosted UI, 4 groups)
                          S3 media bucket (presigned direct uploads)
                          CloudWatch alarms · SNS · AWS Budgets
```

### 6.2 EC2 baseline deployment (for comparison)

The same FastAPI application, packaged as an application zip (backend.zip), runs on an Auto Scaling group of EC2 instances
(`t4g.micro`, min 3 / desired 3 / max 5, scaling on CPU and request count) behind an Application Load Balancer,
reached the same way through CloudFront, and backed by the same RDS and Redis.

### 6.3 Technology stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — single codebase, web build deployed; iOS/Android/desktop targets exist in the project |
| Backend | FastAPI (Python), async I/O throughout, raw SQL via asyncpg (no ORM) |
| Database | Amazon RDS for PostgreSQL 16 — 57 tables, 19 enum types |
| Cache | Amazon ElastiCache for Redis (cache-aside) + CloudFront edge caching |
| Auth | Amazon Cognito, IISc-email-gated sign-up, JWT verified on every route |
| Object storage | Amazon S3 — static site, uploaded media, presigned direct uploads with a signed SHA-256 checksum |
| Infrastructure as code | Terraform (HCL), one module set, two environments (`dev` = serverless, `baseline` = EC2) |
| Observability | CloudWatch logs, metrics and alarms; AWS Budgets |
| Load testing | Locust, with a purpose-built Tkinter GUI, an endpoint catalogue and automated chart generation |

### 6.4 Key design decisions

| Decision | Why |
|---|---|
| FastAPI packaged identically for Lambda (via Mangum) and for EC2 | One codebase runs unmodified in both deployments, which is what makes the architecture comparison meaningful |
| RDS PostgreSQL as the sole system of record | The relational querying needed for combined filters, department→course moderator hierarchies and spreadsheet ingestion is natural in SQL and awkward in a NoSQL store |
| Flutter for the client | One Dart codebase targets web (shipped) and iOS/Android/desktop (scaffolded), with native-quality rendering for photo- and scroll-heavy screens |
| Terraform over CloudFormation | Concise HCL, an explicit `plan` preview before every `apply`, and no cloud-provider lock-in |
| Permissions read from the database on every request, not from JWT claims | A moderator grant or revocation takes effect on the very next API call, with no token refresh needed |
| Redis + CloudFront caching layered in front of Postgres | Cuts p50 latency on the busiest read endpoints without ever caching a write or sharing one user's response with another |
| A second EC2-based deployment of the identical app | Produces real, load-tested numbers for the serverless-vs-always-on trade-off described in the PRD, instead of a theoretical argument |

## 7. Security and data protection

- **Identity**: sign-up is gated to IISc email addresses through Cognito; every API route verifies the bearer
  token (signature, expiry, issuer, audience) and rejects a missing, malformed or expired one.
- **Authorization**: all four roles are enforced per module from the database, including department- and
  course-scoped Academic Help moderators.
- **Transport and storage encryption**: TLS 1.2+ on every public endpoint (CloudFront, RDS `force_ssl`, Redis
  TLS); RDS is encrypted at rest with KMS; application secrets live only in Secrets Manager, never in Lambda
  environment variables.
- **Upload integrity**: every file goes straight to S3 through a presigned URL carrying a signed size limit and
  SHA-256 checksum, which S3 itself enforces before accepting the object.
- **Least privilege**: each AWS service runs under its own IAM role, scoped to only what it needs.
- **Moderation trail**: every moderator action (removal, grant, revocation) is written to an audit log.

## 8. Evaluation: serverless vs. EC2

The two deployments were load-tested with Locust against identical, read-heavy traffic (Academic Help and
Placement Hub endpoints, with a Cognito ID token) at 101 and 501 concurrent users, 2 minutes per run,
bypassing CloudFront's edge cache.

| Stack | Users | Successful req/s | p50 | p95 | p99 | Errors |
|---|---:|---:|---:|---:|---:|---:|
| Lambda | 101 | 54.7 | 53 ms | 74 ms | 140 ms | 0 % |
| EC2 | 101 | 52.5 | 110 ms | 120 ms | 160 ms | 0 % |
| Lambda | 501 | 31.6 | 430 ms | 1,500 ms | 3,500 ms | 84.2 % |
| EC2 | 501 | 94.0 | 440 ms | 13,000 ms | 47,000 ms | 7.2 % |

**At a load of 101 concurrent users, Lambda answers roughly twice as fast as EC2** (53 ms vs. 110 ms median), with
zero errors on both stacks, meeting the PRD's latency target (p99 ≤ 600 ms) and throughput target (≥ 50 req/s).

At higher concurrency, the investigation traced the bottleneck precisely: each of up to 399 concurrent Lambda
containers opened its own database connection pool, which exhausted the `db.t4g.micro` instance's connection
limit (observed peak: 179 simultaneous connections, with thousands of `TooManyConnectionsError`s in the logs).
The fix — Amazon RDS Proxy, which multiplexes a bounded pool of database connections across all Lambda
containers — is already built into the Terraform module (`enable_rds_proxy`) and was simply not switched on
for this run as this is not supported in AWS Free Tier. EC2 degraded differently under the same load (request queuing rather than connection exhaustion).

Full per-endpoint results, interactive reports and charts: [`README.md` §9](README.md#9-performance-and-metrics)
and [`locust_load_testing/output/BENCHMARK_SUMMARY.md`](locust_load_testing/output/BENCHMARK_SUMMARY.md).

## 9. Testing

- **Backend**: over 200 automated tests (pytest) against a real PostgreSQL instance, covering every module's
  CRUD paths and the role/permission checks for all four roles.
- **Frontend**: Flutter widget and integration tests, including a live-backend integration suite.
- **ML feature accuracy**: dedicated accuracy evaluations for Lost & Found matching and category suggestion
  (`docs/auto-flag-accuracy.md`, `docs/category-suggest-accuracy.md`).
- **Load testing**: the Locust suite described in [section 8](#8-evaluation-serverless-vs-ec2), covering 65
  endpoints across 10 modules, runnable against either deployment or a local backend.
- **Deployment verification**: a `curl`-based smoke-test sequence checks health, CloudFront edge caching and
  authentication on every fresh deploy (`README.md` §5.9).

## 10. Team

**Team Order of Phoenix**, DS252 Introduction to Cloud Computing, Indian Institute of Science (IISc).

| SR No. | Name | Email |
|---|---|---|
| 26898 | Mohammad Sufyan Azam | [mohammadazam@iisc.ac.in](mailto:mohammadazam@iisc.ac.in) |
| 26643 | Adithya Chippa | [cadithya@iisc.ac.in](mailto:cadithya@iisc.ac.in) |
| 26648 | Dinky Lakhani | [dinkylakhani@iisc.ac.in](mailto:dinkylakhani@iisc.ac.in) |
| 25862 | Mukund Kukreja | [kmukund@iisc.ac.in](mailto:kmukund@iisc.ac.in) |
