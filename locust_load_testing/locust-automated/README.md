# CampusHub Locust Automation Suite

Modern desktop automation tool for configuring, executing, monitoring, and harvesting performance benchmarks for **CampusHub (DS252 Cloud Computing Project)**.

---

## 🚀 Quick Start

Run the launcher script:
```bash
cd locust_load_testing/locust-automated
./start.sh
```

Or run directly via the dedicated virtual environment:
```bash
locust_load_testing/.venv/bin/python locust_load_testing/locust-automated/app.py
```

---

## ✨ Features & Capabilities

### 1. Target Host & Endpoint Configuration
- **Host Presets:** Quickly toggle between Baseline ALB (`http://campushub-baseline-alb-684305638.ap-south-1.elb.amazonaws.com`) and local development server (`http://localhost:8000`).
- **Complete Route Catalog:** 65 endpoints organized across all 10 CampusHub modules:
  1. System & Health
  2. Profile & Users
  3. Notifications & Alerts
  4. Buy & Sell Marketplace
  5. Academic Help
  6. Community Events & Mess Menus
  7. Lost & Found
  8. Placement Hub
  9. Messaging & Chat
  10. Moderation & Trust

### 2. Smart Cognito Token Handling & Auth Protection
- **Input Sanitization:** Automatically strips leading/trailing spaces, surrounding quotes, tabs, newlines, and `Bearer ` / `bearer ` prefixes.
- **JWT Claim Inspection:** Decodes payload to display student email, user ID (`sub`), expiration timestamp, and remaining validity countdown (e.g., `23m 15s remaining`).
- **Live Verification Button:** Pings the live backend (`GET /api/v1/me`) with `Authorization: Bearer <token>` to confirm real-time authentication before launching.
- **Auth Endpoint Lock:** If no valid token is provided or the token is expired, endpoints requiring authentication are automatically locked and unchecked to prevent unnecessary 401 error storms.

### 3. Presets & Granular Matrix
- **Built-in Presets:**
  - `Academic & Placement Hub (Recommended)`: Focused benchmark evaluating ElastiCache Redis hits, course reviews, and placement directory throughput.
  - `Comprehensive (All 10 Modules)`: Full end-to-end evaluation covering all 65 endpoints.
  - `Minimal (PRD §7 Workload)`: The standard PRD mixed trace (60% marketplace reads, 25% notifications/events, 15% creations).
  - `Read-Only (All GET Endpoints)`: Safe benchmarking with zero database mutations.
  - `Write-Heavy (Creation & Mutating)`: Evaluates DB row locking and mutation performance.
- **Custom Presets:** Save and name custom configurations to disk (`custom_presets/<name>.json`) with one click.
- **Quick Filters:** Buttons for "All Reads", "All Writes", "Select All", and "Clear All", plus module-level "Select / Deselect Module".
- **Custom Weightage:** Every endpoint includes a configurable numeric weight (1–100).

### 4. Locust Execution Engine
- **Multi-Core Scaling:** Automatically spawns worker processes across all CPU cores (`--processes -1`).
- **Web UI & Browser Auto-Launch:** Starts Locust with `--autostart` and automatically opens `http://localhost:8089` in your default browser.
- **Live Metric Cards:** Real-time RPS, active users, failure rate (%), median latency, and p99 SLA latency.
- **Embedded Console:** Live streaming of Locust master and worker terminal logs.

### 5. Automated Data Harvesting & Charts
Each test run creates a dedicated, self-contained subfolder in `locust_load_testing/output/`:
```
locust_load_testing/output/<run_name>_<YYYYMMDD_HHMMSS>_<users>u_<ramp>r_<duration>/
├── run_locustfile.py           # Exact reproducible test file executed
├── live_stats.json             # Real-time metrics snapshot
├── report.html                 # Standalone Locust interactive HTML report (with ECharts)
├── locust_stats_stats.csv      # Detailed per-request statistics CSV
├── locust_stats_stats_history.csv # Second-by-second performance timeline
├── locust_stats_failures.csv   # Failure traces & exception messages
├── chart_throughput_rps.png    # High-resolution RPS & Failures/sec PNG chart
├── chart_response_times.png    # High-resolution p50, p90, p95, p99 latencies PNG chart
├── chart_active_users.png      # Active user ramp timeline PNG chart
└── chart_dashboard.png         # Combined 3-panel performance dashboard PNG
```

---

## 🧹 Database Cleanup Command (PostgreSQL RDS)

To remove all simulated test items (`[LOAD_TEST]`) created in RDS during load testing, run the following SQL command in your database client (psql, DBeaver, pgAdmin):

```sql
BEGIN;

-- 1. Clean up child references
DELETE FROM listing_watches 
 WHERE listing_id IN (SELECT id FROM listings WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%');

DELETE FROM listing_photos 
 WHERE listing_id IN (SELECT id FROM listings WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%');

DELETE FROM reports 
 WHERE listing_id IN (SELECT id FROM listings WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%');

DELETE FROM notifications 
 WHERE payload::text LIKE '%LoadTest%' OR payload::text LIKE '%[LOAD_TEST]%';

-- 2. Delete test listings
DELETE FROM listings 
 WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%';

-- 3. Delete wanted posts, lost/found reports, and interview experiences
DELETE FROM wanted_posts 
 WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%';

DELETE FROM lost_reports 
 WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%';

DELETE FROM found_reports 
 WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%';

DELETE FROM interview_experiences 
 WHERE role_title LIKE '%[LOAD_TEST]%' OR content LIKE '%[LOAD_TEST]%';

COMMIT;

-- Verify cleanup
SELECT count(*) AS remaining_load_test_listings 
  FROM listings 
 WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%';
```
*(You can also click the "RDS Cleanup SQL" button inside the GUI to view and copy this script at any time).*
