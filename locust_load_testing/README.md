# CampusHub Locust Load Testing Suite

Automated desktop benchmark suite with a graphical interface (Tkinter) and distributed multi-core Locust engine for evaluating **CampusHub** on AWS (EC2 Auto Scaling Group vs. AWS Lambda Serverless).

---

## 1. Quick Setup (Virtual Environment)

### Option A: One-Click Automated Launch (Recommended)
The launcher script automatically creates `.venv/`, installs all dependencies, and boots the GUI:
```bash
cd locust_load_testing/locust-automated
./start.sh
```

### Option B: Manual Virtual Environment Setup
```bash
cd locust_load_testing
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
python locust-automated/app.py
```

---

## 2. How to Run

1. **Launch the Application:**
   Run `./start.sh` or `python locust-automated/app.py`.
2. **Select Target Environment:**
   Click **Baseline ALB** (EC2) or **Lambda API** or **Localhost:8000**.
3. **Set Authentication Token:**
   Paste your Amazon Cognito JWT ID token. Click **Verify Token Live** to check validity against `GET /api/v1/me`.
4. **Choose Preset / Endpoints:**
   Select a preset (e.g. `acad_placement_preset` or `minimal_readonly`) or pick individual endpoints and weights.
5. **Configure Locust Parameters:**
   Set Peak Users (`-u`), Spawn Rate (`-r`), Duration (`-t`), and toggle multi-core (`--processes -1`).
6. **Execute:**
   Click **Start Load Test**. The tool automatically spins up master and worker processes, opens the Web UI (`http://localhost:8089`), streams console logs, and tracks real-time RPS, latency, and errors.
7. **Harvest Results:**
   Once completed, click **Open Output** or inspect the generated interactive report and charts in `output/`.

---

## 3. Summary of Features & Options

| Feature | Description |
| :--- | :--- |
| **Target Host Switcher** | 1-click toggles between AWS EC2 ALB, AWS API Gateway (Lambda), and Localhost. |
| **Cognito JWT Inspector** | Decodes token claims, displays student email, expiration time, and remaining validity countdown. |
| **Live Token Validator** | Asynchronously pings the live backend to verify authentication before running. |
| **Endpoint Catalog (65 routes)** | Categorized across 10 modules with individual task weights and realistic pagination parameters (`limit=15`, `limit=20`). |
| **Preset Profiles** | Built-in profiles (`acad_placement_preset`, `minimal_readonly`, `All Reads`) plus 1-click custom preset save/load. |
| **Multi-Core Distributed Engine** | Runs Locust in distributed master-worker mode (`--processes -1`) across all host CPU cores. |
| **Process & Port Guard** | Automatically detects and kills orphaned Locust workers or stale sockets (`5557`, `8089`). |
| **Automated Harvesting** | Generates interactive `report.html`, raw CSV time-series data, and high-resolution PNG charts (`chart_dashboard.png`, `chart_throughput_rps.png`, `chart_response_times.png`). |

---

## 4. Benchmark Results & PRD Traceability

Consolidated benchmark results for EC2 Baseline vs. Lambda Serverless across 101, 250, and 501 concurrent users are documented in:
👉 **[`output/BENCHMARK_SUMMARY.md`](output/BENCHMARK_SUMMARY.md)**

All raw CSV logs, HTML reports, and generated charts for each run are preserved inside the `output/` subdirectories.

---

## 5. Directory Structure

```
locust_load_testing/
├── README.md                      # This documentation
├── requirements.txt               # Python package dependencies
├── locust-automated/              # Test suite source code
│   ├── app.py                     # Tkinter desktop GUI
│   ├── catalog.py                 # 65 endpoints, modules, and route templates
│   ├── generator.py               # Dynamic Locustfile generator
│   ├── runner.py                  # Multi-process Locust execution & cleanup
│   ├── collector.py               # Real-time metrics polling & report download
│   ├── chart_generator.py         # Matplotlib performance charts
│   ├── auth_utils.py              # JWT decoding, sanitization & verification
│   ├── presets.py                 # Preset profile manager
│   ├── start.sh                   # Auto-boot shell launcher
│   └── custom_presets/            # JSON test presets
└── output/                        # Benchmark results & artifacts
    ├── BENCHMARK_SUMMARY.md       # Consolidated empirical evaluation report
    ├── ec2_101users_.../          # EC2 101-user benchmark artifacts
    ├── ec2_250users_.../          # EC2 250-user benchmark artifacts
    ├── ec2_501users_.../          # EC2 501-user benchmark artifacts
    ├── lambda_101users_.../       # Lambda 101-user benchmark artifacts
    ├── lambda_250users_.../       # Lambda 250-user benchmark artifacts
    └── lambda_501users_.../       # Lambda 501-user benchmark artifacts
```
