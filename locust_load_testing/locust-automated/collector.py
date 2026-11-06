"""Background Collector for Locust Stats, HTML Reports and Charts."""
import os
import time
import json
import threading
import urllib.request
import urllib.error
from typing import Dict, Any, List, Optional, Callable
from chart_generator import generate_charts


class MetricsCollector:
    """Polls Locust Web API, updates live stats, saves HTML reports and charts."""

    def __init__(
        self,
        web_port: int,
        output_dir: str,
        csv_history_path: str,
        poll_interval: float = 2.0,
        on_metrics_update: Optional[Callable[[Dict[str, Any]], None]] = None,
        run_title: str = "CampusHub Performance Benchmark"
    ):
        self.web_port = web_port
        self.output_dir = output_dir
        self.csv_history_path = csv_history_path
        self.poll_interval = poll_interval
        self.on_metrics_update = on_metrics_update
        self.run_title = run_title

        self.running = False
        self._thread: Optional[threading.Thread] = None
        self.history: List[Dict[str, Any]] = []
        self.latest_metrics: Dict[str, Any] = {
            "state": "ready",
            "user_count": 0,
            "total_requests": 0,
            "total_failures": 0,
            "current_rps": 0.0,
            "current_fail_per_sec": 0.0,
            "fail_ratio": 0.0,
            "median_response_time": 0.0,
            "p90_response_time": 0.0,
            "p95_response_time": 0.0,
            "p99_response_time": 0.0,
        }

    def start(self):
        """Start background polling thread."""
        self.running = True
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        """Stop polling and generate final reports."""
        self.running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3.0)
        self._save_final_artifacts()

    def _run(self):
        last_chart_gen = time.time()
        while self.running:
            try:
                self._poll_stats()
                # Regenerate charts every 10 seconds or when enough history builds up
                now = time.time()
                if now - last_chart_gen >= 8.0:
                    self._generate_charts_safe()
                    last_chart_gen = now
            except Exception:
                pass
            time.sleep(self.poll_interval)

    def _poll_stats(self):
        base_url = f"http://127.0.0.1:{self.web_port}"
        req_url = f"{base_url}/stats/requests"
        try:
            req = urllib.request.Request(req_url, headers={"User-Agent": "LocustCollector"})
            with urllib.request.urlopen(req, timeout=3.0) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    self._process_stats(data)
        except Exception:
            return

        # Also grab the native standalone HTML report periodically
        report_url = f"{base_url}/stats/report"
        try:
            r_req = urllib.request.Request(report_url, headers={"User-Agent": "LocustCollector"})
            with urllib.request.urlopen(r_req, timeout=4.0) as r_resp:
                if r_resp.status == 200:
                    html_content = r_resp.read()
                    html_path = os.path.join(self.output_dir, "report.html")
                    with open(html_path, "wb") as f:
                        f.write(html_content)
        except Exception:
            pass

    def _process_stats(self, data: Dict[str, Any]):
        stats_list = data.get("stats", [])
        state = data.get("state", "running")
        user_count = data.get("user_count", 0)
        fail_ratio = data.get("fail_ratio", 0.0)

        # Locate Aggregated record
        agg = None
        for s in stats_list:
            if s.get("name") == "Aggregated":
                agg = s
                break

        if not agg and stats_list:
            agg = stats_list[-1]

        if agg:
            now_ts = time.time()
            total_req = agg.get("num_requests", 0)
            total_fail = agg.get("num_failures", 0)
            current_rps = float(agg.get("current_rps", 0.0))
            current_fail_rps = float(agg.get("current_fail_per_sec", 0.0))
            median_ms = float(agg.get("median_response_time", 0.0))
            p90_ms = float(agg.get("response_time_percentile_0.9", 0.0) or agg.get("ninetieth_response_time", 0.0))
            p95_ms = float(agg.get("response_time_percentile_0.95", 0.0) or 0.0)
            p99_ms = float(agg.get("response_time_percentile_0.99", 0.0) or 0.0)

            metrics = {
                "timestamp": now_ts,
                "state": state,
                "user_count": user_count,
                "total_requests": total_req,
                "total_failures": total_fail,
                "current_rps": current_rps,
                "current_fail_per_sec": current_fail_rps,
                "fail_ratio": fail_ratio,
                "median_response_time": median_ms,
                "p90_response_time": p90_ms,
                "p95_response_time": p95_ms,
                "p99_response_time": p99_ms,
            }
            self.latest_metrics = metrics
            self.history.append(metrics)

            # Save snapshot
            snap_path = os.path.join(self.output_dir, "live_stats.json")
            try:
                with open(snap_path, "w", encoding="utf-8") as f:
                    json.dump(metrics, f, indent=2)
            except Exception:
                pass

            if self.on_metrics_update:
                self.on_metrics_update(metrics)

    def _generate_charts_safe(self):
        try:
            generate_charts(
                output_dir=self.output_dir,
                csv_history_path=self.csv_history_path,
                polled_history=self.history,
                run_title=self.run_title
            )
        except Exception:
            pass

    def _save_final_artifacts(self):
        # 1. Final stats snapshot
        base_url = f"http://127.0.0.1:{self.web_port}"
        try:
            report_url = f"{base_url}/stats/report"
            req = urllib.request.Request(report_url, headers={"User-Agent": "LocustCollector"})
            with urllib.request.urlopen(req, timeout=5.0) as resp:
                if resp.status == 200:
                    with open(os.path.join(self.output_dir, "report.html"), "wb") as f:
                        f.write(resp.read())
        except Exception:
            pass

        # 2. Final chart generation
        self._generate_charts_safe()
