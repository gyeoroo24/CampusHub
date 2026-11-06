# CampusHub Performance Benchmark: Baseline EC2 vs. Serverless Lambda

**Document Version:** 1.0  
**Date:** November 6, 2026  
**Evaluation Scope:** Academic & Placement Modules (18–20 Read-Only Endpoints)  
**PRD Traceability:** Validates Section 5 (NFR-1, NFR-2, NFR-3, NFR-4) & Section 7 (Experiment 1: Concurrency and Scalability)  

---

## 1. System Architectures & Test Configurations

### 1.1 Architecture Specifications
- **Proposed Architecture (Serverless Lambda):**
  - **Compute:** AWS Lambda running containerized FastAPI application with Mangum ASGI adapter.
  - **API Ingress:** Amazon API Gateway (HTTP API v2).
  - **Target Host:** `https://5hd795r6zd.execute-api.ap-south-1.amazonaws.com/`
  - **Database:** Amazon RDS PostgreSQL (Single-AZ `db.t4g.micro`, `ap-south-1` Mumbai).
  - **Authentication:** Amazon Cognito User Pool JWT (`ap-south-1_HKXd45Syf`).

- **Baseline Architecture (Always-on EC2):**
  - **Compute:** 3× `t4g.micro` Amazon EC2 instances managed under an Auto Scaling Group (ASG).
  - **API Ingress:** AWS Application Load Balancer (ALB) distributing traffic round-robin.
  - **Target Host:** `http://campushub-baseline-alb-684305638.ap-south-1.elb.amazonaws.com/`
  - **Database:** Shared Amazon RDS PostgreSQL (Single-AZ `db.t4g.micro`, `ap-south-1` Mumbai).
  - **Authentication:** Amazon Cognito User Pool JWT (`ap-south-1_2HPt3OAKg`).

### 1.2 Test Execution Parameters
- **Load Generation Tool:** Locust 2.47.0 executed in distributed multi-core mode (`--processes -1`, utilizes all available host CPU cores).
- **Duration:** 2 minutes (120 seconds) steady-state load per benchmark run.
- **Concurrency Levels Evaluated:**
  1. **101 Users** (Spawn rate: 10 users/sec)
  2. **250 Users** (Spawn rate: 25 users/sec)
  3. **501 Users** (Spawn rate: 25 users/sec)
- **Workload Design:** Realistic student browsing profile across Academic Help and Placement Hub, including pagination parameters (`?limit=15`, `?limit=20`) and randomized seed data IDs.

---

## 2. Consolidated Benchmark Results Matrix

The table below presents the end-to-end empirical measurements recorded across all 6 benchmark runs:

| Architecture | Users | Spawn Rate | Duration | Total Requests | Failures | Failure Rate (%) | Throughput (RPS) | Min (ms) | Avg (ms) | p50 (ms) | p90 (ms) | p95 (ms) | p99 (ms) | Max (ms) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **EC2 (ASG + ALB)** | 101 | 10/s | 2m | 6,306 | 0 | **0.00%** | **52.53** | 31.5 | 104.6 | 110.0 | 120.0 | 120.0 | **160.0** | 375.3 |
| **EC2 (ASG + ALB)** | 250 | 25/s | 2m | 9,616 | 2,965 | **30.83%** | **80.05** | 32.1 | 1304.0 | 130.0 | 3200.0 | 5800.0 | **24000.0** | 60090.9 |
| **EC2 (ASG + ALB)** | 501 | 25/s | 2m | 12,168 | 871 | **7.16%** | **101.29** | 32.1 | 2907.3 | 440.0 | 8300.0 | 13000.0 | **47000.0** | 61266.1 |
| **AWS Lambda + API GW** | 101 | 10/s | 2m | 6,566 | 0 | **0.00%** | **54.69** | 41.3 | 73.8 | 53.0 | 67.0 | 74.0 | **140.0** | 4764.5 |
| **AWS Lambda + API GW** | 250 | 25/s | 2m | 14,621 | 13,000 | **88.91%** | **121.79** | 40.5 | 182.6 | 150.0 | 190.0 | 280.0 | **3200.0** | 6131.3 |
| **AWS Lambda + API GW** | 501 | 25/s | 2m | 24,002 | 20,204 | **84.18%** | **199.84** | 35.7 | 556.8 | 430.0 | 860.0 | 1500.0 | **3500.0** | 7163.8 |

---

## 3. PRD Non-Functional Requirements (NFR) Compliance Matrix

Evaluation against Section 5 of the CampusHub PRD (`CampusHub-PRD-v1.pdf`):

| PRD Requirement ID | Target Metric | Target Value | Measured Baseline (EC2 101u) | Measured Serverless (Lambda 101u) | Compliance Status |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **NFR-1 (Latency)** | End-to-End Latency (p99) | **≤ 600 ms** (incl. cold starts) | **160.0 ms** | **140.0 ms** | **PASSED** (Both architectures exceed target) |
| **NFR-2 (Throughput)** | Aggregate Throughput | **≥ 50 req/s** | **52.53 req/s** | **54.69 req/s** | **PASSED** (Both exceed 50 req/s threshold) |
| **NFR-2 (Error Rate)** | Error Rate Ceiling | **< 1.0%** | **0.00%** (0 / 6,306) | **0.00%** (0 / 6,566) | **PASSED** (Zero failures recorded) |
| **NFR-4 (High Availability)** | Availability Percentage | **≥ 99.0%** | **100.0%** | **100.0%** | **PASSED** |

### High-Concurrency Scalability Evaluation (PRD NFR-3)
- **NFR-3 Target:** `≥ 500 concurrent sessions without p99 exceeding NFR-1 by > 2×` (i.e. **p99 ≤ 1,200 ms** at 500 users).

| Concurrency Level | Architecture | Measured RPS | Measured p99 (ms) | Target p99 Threshold | Failure Rate (%) | NFR-3 Compliance |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: |
| **250 Users** | EC2 Baseline | 80.05 req/s | 24,000.0 ms | ≤ 1,200 ms | 30.83% | **FAILED** (High latency & 500/502 errors) |
| **250 Users** | Lambda Serverless | 121.79 req/s | 3,200.0 ms | ≤ 1,200 ms | 88.91% | **FAILED** (DB connection pool exhaustion) |
| **501 Users** | EC2 Baseline | 101.29 req/s | 47,000.0 ms | ≤ 1,200 ms | 7.16% | **FAILED** (Severe queueing & timeouts) |
| **501 Users** | Lambda Serverless | 199.84 req/s | 3,500.0 ms | ≤ 1,200 ms | 84.18% | **FAILED** (DB connection pool exhaustion) |

---

## 4. Error & Failure Breakdown

Detailed classification of HTTP status codes and error responses encountered across the test suite:

| Configuration | Total Requests | Total Failures | Failure % | HTTP 500 | HTTP 502 | HTTP 503 | HTTP 504 | Primary Failure Cause |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **EC2 Baseline - 101 Users** | 6,306 | 0 | **0.00%** | 0 | 0 | 0 | 0 | None (100% Success) |
| **EC2 Baseline - 250 Users** | 9,616 | 2,965 | **30.83%** | 2,912 | 52 | 0 | 1 | PostgreSQL pool exhaustion (500) & ALB upstream drops (502) |
| **EC2 Baseline - 501 Users** | 12,168 | 871 | **7.16%** | 725 | 78 | 0 | 68 | High request queueing (500), ALB bad gateway (502) & timeouts (504) |
| **Lambda Serverless - 101 Users** | 6,566 | 0 | **0.00%** | 0 | 0 | 0 | 0 | None (100% Success) |
| **Lambda Serverless - 250 Users** | 14,621 | 13,000 | **88.91%** | 13,000 | 0 | 0 | 0 | RDS PostgreSQL max connection limit reached by Lambda scale-out (500) |
| **Lambda Serverless - 501 Users** | 24,002 | 20,204 | **84.18%** | 20,197 | 0 | 7 | 0 | RDS connection saturation (500) & API GW service throttling (503) |

---

## 5. Endpoints Tested & Workload Specification

The benchmark workload executed an Academic and Placement test suite comprising 18 read-only endpoints plus 2 pre-flight verification endpoints:

| Module | HTTP Method | Endpoint URI & Query Parameters | Weight | Purpose |
| :--- | :---: | :--- | :---: | :--- |
| **Core** | `GET` | `/api/v1/health` | 5 | Fast baseline infrastructure health ping |
| **Academic** | `GET` | `/api/v1/departments` | 6 | Department directory listing |
| **Academic** | `GET` | `/api/v1/departments/{id}/courses` | 8 | Courses offered under department (seeded CDS dept) |
| **Academic** | `GET` | `/api/v1/courses/{id}` | 6 | Detailed course information lookup |
| **Academic** | `GET` | `/api/v1/courses/{id}/feedback?limit=15` | 12 | Student course reviews and ratings (paginated) |
| **Academic** | `GET` | `/api/v1/courses/{id}/materials?limit=20` | 4 | Course syllabus, notes, and past exam materials |
| **Academic** | `GET` | `/api/v1/courses/{id}/survival-guide` | 4 | Student tips and course survival guide |
| **Academic** | `GET` | `/api/v1/courses/{id}/forum?limit=15` | 4 | Course Q&A and discussion forum threads |
| **Placement** | `GET` | `/api/v1/companies?limit=20&sort={sort_mode}` | 8 | Company directory with randomized sort & limit |
| **Placement** | `GET` | `/api/v1/companies/{id}` | 4 | Company details and job description |
| **Placement** | `GET` | `/api/v1/companies/{id}/hiring-stats` | 4 | Multi-year historical placement hiring statistics |
| **Placement** | `GET` | `/api/v1/companies/{id}/seniors?limit=20` | 4 | Senior student alumni network contacts |
| **Placement** | `GET` | `/api/v1/companies/{id}/forum?limit=15` | 3 | Company interview discussion forum |
| **Placement** | `GET` | `/api/v1/placement/stats` | 5 | Aggregated university placement overview stats |
| **Placement** | `GET` | `/api/v1/interviews?limit=15` | 5 | Interview experiences listing feed |
| **Placement** | `GET` | `/api/v1/interviews/{id}` | 3 | Individual student interview experience detail |
| **Placement** | `GET` | `/api/v1/placement/ppts?limit=20` | 4 | Pre-Placement Talk (PPT) schedules and decks |
| **Init / Auth** | `GET` | `/api/v1/listings?limit=5` | Init | Client session pre-flight warm-up & token check |
| **Init / Auth** | `GET` | `/api/v1/companies?limit=5` | Init | Client session pre-flight company seed check |

---

## 6. Granular Per-Endpoint Performance Breakdown

### 6.1 Baseline Comparison at 101 Users (0.00% Failure Rate)

Side-by-side performance of all endpoints when operating under normal load without resource saturation:

| Endpoint Name | EC2 Reqs | EC2 RPS | EC2 p50 (ms) | EC2 p95 (ms) | EC2 p99 (ms) | Lambda Reqs | Lambda RPS | Lambda p50 (ms) | Lambda p95 (ms) | Lambda p99 (ms) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `/api/v1/companies [Init]` | 101 | 0.84 | 140 | 210 | 240 | 101 | 0.84 | 88 | 3600 | 4100 |
| `/api/v1/listings [Init]` | 101 | 0.84 | 94 | 150 | 340 | 101 | 0.84 | 130 | 4400 | 4700 |
| `[Academic] GET /api/v1/courses/{id}` | 455 | 3.79 | 100 | 110 | 130 | 441 | 3.67 | 50 | 60 | 81 |
| `[Academic] GET /api/v1/courses/{id}/feedback` | 852 | 7.10 | 110 | 120 | 140 | 884 | 7.36 | 53 | 64 | 78 |
| `[Academic] GET /api/v1/courses/{id}/forum` | 312 | 2.60 | 100 | 110 | 130 | 275 | 2.29 | 49 | 56 | 69 |
| `[Academic] GET /api/v1/courses/{id}/materials` | 262 | 2.18 | 110 | 110 | 130 | 286 | 2.38 | 53 | 64 | 390 |
| `[Academic] GET /api/v1/courses/{id}/survival-guide` | 258 | 2.15 | 110 | 120 | 170 | 295 | 2.46 | 63 | 75 | 94 |
| `[Academic] GET /api/v1/departments` | 435 | 3.62 | 100 | 110 | 160 | 447 | 3.72 | 49 | 59 | 96 |
| `[Academic] GET /api/v1/departments/{id}/courses` | 582 | 4.85 | 100 | 120 | 140 | 561 | 4.67 | 52 | 65 | 97 |
| `[Core] GET /api/v1/health` | 341 | 2.84 | 35 | 40 | 57 | 375 | 3.12 | 47 | 55 | 71 |
| `[Placement] GET /api/v1/companies/{id}` | 279 | 2.32 | 110 | 120 | 140 | 309 | 2.57 | 55 | 64 | 78 |
| `[Placement] GET /api/v1/companies/{id}/forum` | 217 | 1.81 | 100 | 110 | 130 | 192 | 1.60 | 50 | 60 | 130 |
| `[Placement] GET /api/v1/companies/{id}/hiring-stats` | 309 | 2.57 | 110 | 110 | 130 | 302 | 2.52 | 52 | 63 | 71 |
| `[Placement] GET /api/v1/companies/{id}/seniors` | 265 | 2.21 | 110 | 130 | 140 | 292 | 2.43 | 53 | 62 | 69 |
| `[Placement] GET /api/v1/companies?limit=20` | 553 | 4.61 | 120 | 130 | 170 | 571 | 4.76 | 66 | 78 | 110 |
| `[Placement] GET /api/v1/interviews/{id}` | - | - | - | - | - | 151 | 1.26 | 50 | 56 | 70 |
| `[Placement] GET /api/v1/interviews?limit=15` | 351 | 2.92 | 100 | 110 | 150 | 370 | 3.08 | 53 | 63 | 86 |
| `[Placement] GET /api/v1/placement/ppts?limit=20` | 295 | 2.46 | 100 | 110 | 140 | 294 | 2.45 | 51 | 61 | 110 |
| `[Placement] GET /api/v1/placement/stats` | 338 | 2.82 | 110 | 120 | 130 | 319 | 2.66 | 59 | 70 | 110 |

### 6.2 EC2 Baseline Endpoint Breakdown Across Concurrency Levels

| Endpoint Name | 101u Reqs | 101u p99 (ms) | 250u Reqs | 250u Fail % | 250u p99 (ms) | 501u Reqs | 501u Fail % | 501u p99 (ms) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `/api/v1/companies [Init]` | 101 | 240 | 250 | 0.8% | 15000 | 501 | 1.4% | 41000 |
| `/api/v1/listings [Init]` | 101 | 340 | 250 | 3.6% | 33000 | 501 | 4.4% | 60000 |
| `[Academic] GET /api/v1/courses/{id}` | 455 | 130 | 632 | 30.4% | 41000 | 805 | 7.2% | 21000 |
| `[Academic] GET /api/v1/courses/{id}/feedback` | 852 | 140 | 1,290 | 32.2% | 13000 | 1,561 | 7.6% | 50000 |
| `[Academic] GET /api/v1/courses/{id}/forum` | 312 | 130 | 438 | 31.7% | 12000 | 534 | 6.7% | 20000 |
| `[Academic] GET /api/v1/courses/{id}/materials` | 262 | 130 | 416 | 34.6% | 15000 | 492 | 9.1% | 24000 |
| `[Academic] GET /api/v1/courses/{id}/survival-guide` | 258 | 170 | 404 | 31.7% | 9200 | 504 | 6.2% | 48000 |
| `[Academic] GET /api/v1/departments` | 435 | 160 | 602 | 30.6% | 29000 | 754 | 9.8% | 60000 |
| `[Academic] GET /api/v1/departments/{id}/courses` | 582 | 140 | 857 | 32.4% | 15000 | 1,084 | 7.2% | 47000 |
| `[Core] GET /api/v1/health` | 341 | 57 | 512 | 31.2% | 14000 | 633 | 7.9% | 47000 |
| `[Placement] GET /api/v1/companies/{id}` | 279 | 140 | 413 | 35.4% | 16000 | 502 | 7.6% | 24000 |
| `[Placement] GET /api/v1/companies/{id}/forum` | 217 | 130 | 304 | 30.3% | 24000 | 374 | 5.6% | 22000 |
| `[Placement] GET /api/v1/companies/{id}/hiring-stats` | 309 | 130 | 437 | 35.0% | 24000 | 554 | 7.2% | 57000 |
| `[Placement] GET /api/v1/companies/{id}/seniors` | 265 | 140 | 429 | 28.4% | 25000 | 508 | 7.7% | 29000 |
| `[Placement] GET /api/v1/companies?limit=20` | 553 | 170 | 869 | 34.8% | 42000 | 1,044 | 7.0% | 29000 |
| `[Placement] GET /api/v1/interviews?limit=15` | 351 | 150 | 536 | 34.0% | 15000 | 666 | 6.9% | 22000 |
| `[Placement] GET /api/v1/placement/ppts?limit=20` | 295 | 140 | 447 | 32.9% | 41000 | 496 | 8.3% | 60000 |
| `[Placement] GET /api/v1/placement/stats` | 338 | 130 | 530 | 32.1% | 11000 | 655 | 8.2% | 60000 |

### 6.3 Lambda Serverless Endpoint Breakdown Across Concurrency Levels

| Endpoint Name | 101u Reqs | 101u p99 (ms) | 250u Reqs | 250u Fail % | 250u p99 (ms) | 501u Reqs | 501u Fail % | 501u p99 (ms) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `/api/v1/companies [Init]` | 101 | 4100 | 250 | 18.8% | 5900 | 501 | 20.8% | 4900 |
| `/api/v1/listings [Init]` | 101 | 4700 | 250 | 8.0% | 5600 | 501 | 17.0% | 3900 |
| `[Academic] GET /api/v1/courses/{id}` | 441 | 81 | 999 | 98.4% | 1300 | 1,479 | 88.2% | 3900 |
| `[Academic] GET /api/v1/courses/{id}/feedback` | 884 | 78 | 2,017 | 98.0% | 710 | 3,128 | 88.6% | 3400 |
| `[Academic] GET /api/v1/courses/{id}/feedback/mine` | - | - | - | - | - | 1,067 | 87.6% | 3300 |
| `[Academic] GET /api/v1/courses/{id}/forum` | 275 | 69 | 654 | 97.1% | 450 | 1,035 | 88.4% | 3500 |
| `[Academic] GET /api/v1/courses/{id}/materials` | 286 | 390 | 673 | 97.6% | 3500 | 1,036 | 87.3% | 3800 |
| `[Academic] GET /api/v1/courses/{id}/survival-guide` | 295 | 94 | 688 | 98.1% | 1100 | 1,009 | 89.1% | 4100 |
| `[Academic] GET /api/v1/departments` | 447 | 96 | 1,016 | 97.3% | 890 | 1,563 | 87.0% | 3400 |
| `[Academic] GET /api/v1/departments/{id}/courses` | 561 | 97 | 1,322 | 97.9% | 700 | 2,055 | 89.7% | 3400 |
| `[Core] GET /api/v1/health` | 375 | 71 | 850 | 0.0% | 160 | 1,277 | 88.6% | 3300 |
| `[Placement] GET /api/v1/companies/{id}` | 309 | 78 | 535 | 97.8% | 1000 | 915 | 85.5% | 3600 |
| `[Placement] GET /api/v1/companies/{id}/forum` | 192 | 130 | 423 | 96.7% | 640 | 628 | 83.8% | 2800 |
| `[Placement] GET /api/v1/companies/{id}/hiring-stats` | 302 | 71 | 547 | 95.4% | 810 | 899 | 84.5% | 2800 |
| `[Placement] GET /api/v1/companies/{id}/seniors` | 292 | 69 | 569 | 97.5% | 450 | 894 | 84.5% | 3500 |
| `[Placement] GET /api/v1/companies?limit=20` | 571 | 110 | 1,384 | 97.4% | 690 | 2,125 | 85.5% | 3400 |
| `[Placement] GET /api/v1/interviews/{id}` | 151 | 70 | 47 | 97.9% | 470 | 214 | 90.7% | 2600 |
| `[Placement] GET /api/v1/interviews?limit=15` | 370 | 86 | 801 | 96.4% | 450 | 1,372 | 85.9% | 3500 |
| `[Placement] GET /api/v1/placement/ppts?limit=20` | 294 | 110 | 704 | 97.3% | 550 | 998 | 84.1% | 2600 |
| `[Placement] GET /api/v1/placement/stats` | 319 | 110 | 892 | 96.9% | 1200 | 1,306 | 84.5% | 3500 |

---

## 7. Artifacts Index & Directory Structure

All raw datasets, execution scripts, HTML reports, and generated charts are preserved in the `locust_load_testing/output/` directory:

| Benchmark Run | Folder Path | Key Artifacts Available |
| :--- | :--- | :--- |
| **EC2 Baseline - 101 Users** | `locust_load_testing/output/ec2_101users_acad_placement_20261106_203135_101u_10r_2m/` | `report.html`, `locust_stats_stats.csv`, `locust_stats_failures.csv`, `chart_dashboard.png`, `chart_throughput_rps.png`, `chart_response_times.png` |
| **EC2 Baseline - 250 Users** | `locust_load_testing/output/ec2_250users_acad_placement_20261106_215129_250u_25r_2m/` | `report.html`, `locust_stats_stats.csv`, `locust_stats_failures.csv`, `chart_dashboard.png`, `chart_throughput_rps.png`, `chart_response_times.png` |
| **EC2 Baseline - 501 Users** | `locust_load_testing/output/ec2_501users_acad_placement_20261106_211502_501u_25r_2m/` | `report.html`, `locust_stats_stats.csv`, `locust_stats_failures.csv`, `chart_dashboard.png`, `chart_throughput_rps.png`, `chart_response_times.png` |
| **Lambda Serverless - 101 Users** | `locust_load_testing/output/lambda_101users_acad_placement_20261106_195430_101u_10r_2m/` | `report.html`, `locust_stats_stats.csv`, `locust_stats_failures.csv`, `chart_dashboard.png`, `chart_throughput_rps.png`, `chart_response_times.png` |
| **Lambda Serverless - 250 Users** | `locust_load_testing/output/lambda_250users_acad_placement_20261106_193701_250u_25r_2m/` | `report.html`, `locust_stats_stats.csv`, `locust_stats_failures.csv`, `chart_dashboard.png`, `chart_throughput_rps.png`, `chart_response_times.png` |
| **Lambda Serverless - 501 Users** | `locust_load_testing/output/lambda_501users_acad_placement_20261106_180806_501u_25r_2m/` | `report.html`, `locust_stats_stats.csv`, `locust_stats_failures.csv`, `chart_dashboard.png`, `chart_throughput_rps.png`, `chart_response_times.png` |

- **Raw Runs Directory:** `locust_load_testing/output/`

