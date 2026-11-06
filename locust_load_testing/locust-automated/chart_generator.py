"""Chart Generator for CampusHub Load Testing.

Generates high-resolution PNG charts from Locust stats history or polled metrics:
  - Throughput (RPS & Failures/s)
  - Latency Percentiles (p50, p90, p95, p99)
  - Active Users ramp-up
  - Combined 3-panel Performance Dashboard
"""
import os
import csv
from typing import List, Dict, Any, Optional

import matplotlib
matplotlib.use("Agg")  # Thread-safe headless backend
import matplotlib.pyplot as plt


def parse_history_csv(csv_path: str) -> Dict[str, List[float]]:
    """Parse Locust _stats_history.csv for Aggregated records."""
    data = {
        "time": [],
        "users": [],
        "rps": [],
        "failures_s": [],
        "p50": [],
        "p90": [],
        "p95": [],
        "p99": [],
    }
    if not os.path.exists(csv_path):
        return data

    t0 = None
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            # We only want the total aggregated row for each timestamp
            name = row.get("Name", "")
            if name != "Aggregated":
                continue

            try:
                ts = float(row.get("Timestamp", 0))
                if t0 is None:
                    t0 = ts
                elapsed = ts - t0

                users = float(row.get("User Count", 0))
                rps = float(row.get("Requests/s", 0))
                fps = float(row.get("Failures/s", 0))
                p50 = float(row.get("50%", 0) or 0)
                p90 = float(row.get("90%", 0) or 0)
                p95 = float(row.get("95%", 0) or 0)
                p99 = float(row.get("99%", 0) or 0)

                data["time"].append(elapsed)
                data["users"].append(users)
                data["rps"].append(rps)
                data["failures_s"].append(fps)
                data["p50"].append(p50)
                data["p90"].append(p90)
                data["p95"].append(p95)
                data["p99"].append(p99)
            except Exception:
                continue

    return data


def generate_charts(
    output_dir: str,
    csv_history_path: Optional[str] = None,
    polled_history: Optional[List[Dict[str, Any]]] = None,
    run_title: str = "CampusHub Performance Benchmark"
) -> Dict[str, str]:
    """Generate PNG charts in output_dir.
    
    Returns dict mapping chart_name -> file_path.
    """
    os.makedirs(output_dir, exist_ok=True)
    generated = {}

    # Extract data from CSV or fallback to polled in-memory history
    data = {"time": [], "users": [], "rps": [], "failures_s": [], "p50": [], "p90": [], "p95": [], "p99": []}
    if csv_history_path and os.path.exists(csv_history_path):
        data = parse_history_csv(csv_history_path)

    if not data["time"] and polled_history:
        t0 = None
        for item in polled_history:
            ts = item.get("timestamp", 0)
            if t0 is None:
                t0 = ts
            elapsed = ts - t0
            data["time"].append(elapsed)
            data["users"].append(item.get("user_count", 0))
            data["rps"].append(item.get("current_rps", 0))
            data["failures_s"].append(item.get("current_fail_per_sec", 0))
            data["p50"].append(item.get("median_response_time", 0))
            data["p90"].append(item.get("p90_response_time", 0))
            data["p95"].append(item.get("p95_response_time", 0))
            data["p99"].append(item.get("p99_response_time", 0))

    if len(data["time"]) < 2:
        return generated

    time_pts = data["time"]

    # 1. Throughput Chart (RPS & Failures)
    fig, ax = plt.subplots(figsize=(10, 4.5), dpi=150)
    ax.plot(time_pts, data["rps"], label="Total Requests / sec", color="#1f77b4", linewidth=2)
    if any(f > 0 for f in data["failures_s"]):
        ax.plot(time_pts, data["failures_s"], label="Failures / sec", color="#d62728", linewidth=2, linestyle="--")
    ax.set_title(f"{run_title} - Throughput (RPS)", fontsize=13, fontweight="bold", pad=10)
    ax.set_xlabel("Elapsed Time (seconds)", fontsize=11)
    ax.set_ylabel("Requests per Second", fontsize=11)
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend(loc="upper left")
    plt.tight_layout()
    rps_path = os.path.join(output_dir, "chart_throughput_rps.png")
    fig.savefig(rps_path)
    plt.close(fig)
    generated["throughput"] = rps_path

    # 2. Response Times (p50, p90, p95, p99)
    fig, ax = plt.subplots(figsize=(10, 4.5), dpi=150)
    ax.plot(time_pts, data["p50"], label="50th Percentile (Median)", color="#2ca02c", linewidth=1.8)
    ax.plot(time_pts, data["p90"], label="90th Percentile", color="#ff7f0e", linewidth=1.8)
    ax.plot(time_pts, data["p95"], label="95th Percentile", color="#9467bd", linewidth=1.8)
    ax.plot(time_pts, data["p99"], label="99th Percentile (p99 SLA)", color="#d62728", linewidth=2.2)
    ax.set_title(f"{run_title} - Response Times (ms)", fontsize=13, fontweight="bold", pad=10)
    ax.set_xlabel("Elapsed Time (seconds)", fontsize=11)
    ax.set_ylabel("Latency (ms)", fontsize=11)
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend(loc="upper left")
    plt.tight_layout()
    lat_path = os.path.join(output_dir, "chart_response_times.png")
    fig.savefig(lat_path)
    plt.close(fig)
    generated["latency"] = lat_path

    # 3. Active Users Chart
    fig, ax = plt.subplots(figsize=(10, 3.5), dpi=150)
    ax.plot(time_pts, data["users"], label="Simulated Concurrent Users", color="#008080", linewidth=2)
    ax.fill_between(time_pts, data["users"], color="#008080", alpha=0.15)
    ax.set_title(f"{run_title} - Active Users Ramp-up", fontsize=13, fontweight="bold", pad=10)
    ax.set_xlabel("Elapsed Time (seconds)", fontsize=11)
    ax.set_ylabel("Concurrent Users", fontsize=11)
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend(loc="upper left")
    plt.tight_layout()
    users_path = os.path.join(output_dir, "chart_active_users.png")
    fig.savefig(users_path)
    plt.close(fig)
    generated["users"] = users_path

    # 4. Combined 3-Panel Dashboard
    fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(11, 10), dpi=150, sharex=True)
    fig.suptitle(f"{run_title} - Performance Dashboard", fontsize=14, fontweight="bold", y=0.98)

    # Panel 1: RPS
    ax1.plot(time_pts, data["rps"], label="Requests / sec", color="#1f77b4", linewidth=1.8)
    if any(f > 0 for f in data["failures_s"]):
        ax1.plot(time_pts, data["failures_s"], label="Failures / sec", color="#d62728", linewidth=1.8, linestyle="--")
    ax1.set_ylabel("Req / s", fontsize=10)
    ax1.grid(True, linestyle=":", alpha=0.6)
    ax1.legend(loc="upper left", fontsize=9)

    # Panel 2: Latencies
    ax2.plot(time_pts, data["p50"], label="p50", color="#2ca02c", linewidth=1.5)
    ax2.plot(time_pts, data["p90"], label="p90", color="#ff7f0e", linewidth=1.5)
    ax2.plot(time_pts, data["p95"], label="p95", color="#9467bd", linewidth=1.5)
    ax2.plot(time_pts, data["p99"], label="p99", color="#d62728", linewidth=2.0)
    ax2.set_ylabel("Latency (ms)", fontsize=10)
    ax2.grid(True, linestyle=":", alpha=0.6)
    ax2.legend(loc="upper left", fontsize=9)

    # Panel 3: Users
    ax3.plot(time_pts, data["users"], label="Users", color="#008080", linewidth=1.8)
    ax3.fill_between(time_pts, data["users"], color="#008080", alpha=0.15)
    ax3.set_xlabel("Elapsed Time (seconds)", fontsize=10)
    ax3.set_ylabel("Users", fontsize=10)
    ax3.grid(True, linestyle=":", alpha=0.6)
    ax3.legend(loc="upper left", fontsize=9)

    plt.tight_layout(rect=[0, 0.03, 1, 0.96])
    dash_path = os.path.join(output_dir, "chart_dashboard.png")
    fig.savefig(dash_path)
    plt.close(fig)
    generated["dashboard"] = dash_path

    return generated
