"""Subprocess execution manager for Locust load tests."""
import os
import sys
import time
import signal
import shutil
import subprocess
import threading
import webbrowser
from typing import Optional, Callable, Dict, Any
import psutil

from collector import MetricsCollector


def cleanup_stale_locust_processes(logger: Optional[Callable[[str], None]] = None):
    """Ensure no stale locust instances or lingering workers are hogging ports 5557 or 8089."""
    current_pid = os.getpid()
    killed = 0

    # 1. Kill any locust python processes
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.pid == current_pid:
                continue
            cmdline = " ".join(proc.info.get('cmdline') or [])
            if "locust" in cmdline and ("--processes" in cmdline or "locustfile" in cmdline or "run_locustfile" in cmdline):
                proc.kill()
                killed += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    # 2. Check ports 5557 (ZMQ master) and 8089 (Web UI)
    for port in (5557, 8089):
        try:
            for conn in psutil.net_connections(kind='inet'):
                if conn.laddr and conn.laddr.port == port and conn.pid and conn.pid != current_pid:
                    try:
                        p = psutil.Process(conn.pid)
                        p.kill()
                        killed += 1
                    except Exception:
                        pass
        except Exception:
            pass

    if killed > 0 and logger:
        logger(f"Cleaned up {killed} lingering Locust process(es) and freed port 5557 / 8089.")
    time.sleep(0.6)


def find_locust_executable() -> str:
    """Find locust executable in local venv or system PATH."""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    venv_locust = os.path.join(base_dir, ".venv", "bin", "locust")
    if os.path.isfile(venv_locust) and os.access(venv_locust, os.X_OK):
        return venv_locust
    
    # Check parent venvs
    for parent in [
        os.path.join(base_dir, "..", "baseline-ec2-deployment", "backend", ".venv", "bin", "locust"),
        os.path.join(base_dir, "..", "campushub-v3", "backend", ".venv", "bin", "locust"),
    ]:
        p = os.path.abspath(parent)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p

    which_locust = shutil.which("locust")
    if which_locust:
        return which_locust
        
    raise RuntimeError("Could not find Locust executable. Please check perf_test/.venv installation.")


class LocustRunner:
    """Manages spawning, streaming logs, web UI opening, and clean shutdown of Locust."""

    def __init__(
        self,
        locustfile_path: str,
        host: str,
        output_dir: str,
        users: int = 50,
        spawn_rate: float = 10.0,
        run_time: Optional[str] = "2m",
        processes: int = -1,
        web_port: int = 8089,
        run_title: str = "CampusHub Performance Benchmark",
        log_callback: Optional[Callable[[str], None]] = None,
        metrics_callback: Optional[Callable[[Dict[str, Any]], None]] = None,
        on_finish_callback: Optional[Callable[[int], None]] = None,
    ):
        self.locustfile_path = locustfile_path
        self.host = host
        self.output_dir = output_dir
        self.users = users
        self.spawn_rate = spawn_rate
        self.run_time = run_time
        self.processes = processes
        self.web_port = web_port
        self.run_title = run_title
        self.log_callback = log_callback
        self.metrics_callback = metrics_callback
        self.on_finish_callback = on_finish_callback

        self.proc: Optional[subprocess.Popen] = None
        self.collector: Optional[MetricsCollector] = None
        self.is_running = False
        self._monitor_thread: Optional[threading.Thread] = None

    def start(self, open_browser: bool = True):
        """Launch Locust master and workers."""
        # 1. Clean up any lingering processes from previous tests
        cleanup_stale_locust_processes(self._log)

        locust_bin = find_locust_executable()
        os.makedirs(self.output_dir, exist_ok=True)

        csv_prefix = os.path.join(self.output_dir, "locust_stats")
        csv_history_path = f"{csv_prefix}_stats_history.csv"
        html_report_path = os.path.join(self.output_dir, "report.html")

        cmd = [
            locust_bin,
            "-f", self.locustfile_path,
            "--host", self.host,
            "--users", str(self.users),
            "--spawn-rate", str(self.spawn_rate),
            "--web-port", str(self.web_port),
            "--autostart",
            "--csv", csv_prefix,
            "--csv-full-history",
            "--html", html_report_path,
        ]

        if self.run_time and self.run_time.strip().lower() not in ("unlimited", "0", "none", ""):
            cmd.extend(["--run-time", self.run_time.strip(), "--autoquit", "5"])

        if self.processes != 0:
            cmd.extend(["--processes", str(self.processes)])

        self._log(f"Starting Locust Benchmark...")
        self._log(f"Command: {' '.join(cmd)}")
        self._log(f"Artifacts output directory: {self.output_dir}")

        # Start process with preexec_fn for independent process group (clean group kill)
        self.proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            preexec_fn=os.setsid
        )
        self.is_running = True

        # Initialize background metrics and chart collector
        self.collector = MetricsCollector(
            web_port=self.web_port,
            output_dir=self.output_dir,
            csv_history_path=csv_history_path,
            poll_interval=2.0,
            on_metrics_update=self.metrics_callback,
            run_title=self.run_title
        )
        self.collector.start()

        # Start monitoring stdout/stderr
        self._monitor_thread = threading.Thread(target=self._read_output, daemon=True)
        self._monitor_thread.start()

        # Open web UI in browser after short delay
        if open_browser:
            threading.Thread(target=self._delayed_browser_open, daemon=True).start()

    def _delayed_browser_open(self):
        time.sleep(2.0)
        web_url = f"http://127.0.0.1:{self.web_port}"
        try:
            webbrowser.open(web_url)
            self._log(f"Opened Locust Web Interface at {web_url}")
        except Exception:
            self._log(f"Locust Web UI available at {web_url}")

    def _read_output(self):
        """Stream stdout line by line to console callback."""
        if not self.proc or not self.proc.stdout:
            return

        for line in self.proc.stdout:
            self._log(line.rstrip("\n"))

        self.proc.wait()
        exit_code = self.proc.returncode
        self.is_running = False

        self._log(f"Locust process exited with status code {exit_code}")
        if self.collector:
            self.collector.stop()

        if self.on_finish_callback:
            self.on_finish_callback(exit_code)

    def stop(self):
        """Terminate master and all worker processes cleanly."""
        if not self.proc or not self.is_running:
            cleanup_stale_locust_processes(self._log)
            return

        self._log("Stopping Locust test run (SIGTERM to process group)...")
        try:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
        except Exception as exc:
            self._log(f"Notice during shutdown: {exc}")

        # Wait briefly for graceful shutdown, else SIGKILL
        try:
            self.proc.wait(timeout=3.0)
        except subprocess.TimeoutExpired:
            self._log("Force killing lingering worker processes (SIGKILL)...")
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except Exception:
                pass

        cleanup_stale_locust_processes(self._log)
        self.is_running = False
        if self.collector:
            self.collector.stop()
        self._log("Locust test terminated.")

    def _log(self, message: str):
        if self.log_callback:
            self.log_callback(message)
        else:
            print(f"[LocustRunner] {message}")
