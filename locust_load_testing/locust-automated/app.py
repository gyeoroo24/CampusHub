#!/usr/bin/env python3
"""CampusHub Automated Locust Performance Testing Suite.

Tkinter GUI for configuring, running, monitoring, and automatically harvesting
benchmarks for CampusHub on AWS (EC2/Lambda) and Localhost.
"""
import os
import sys
import time
import threading
import subprocess
import webbrowser
from datetime import datetime
from typing import Dict, Any, List, Optional

import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext, simpledialog

# Ensure local modules are importable
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from catalog import MODULES, ENDPOINTS, ENDPOINTS_MAP, Endpoint
from auth_utils import sanitize_token, decode_jwt, test_token_live
from presets import (
    get_default_presets,
    list_custom_presets,
    save_custom_preset,
    load_custom_preset,
    delete_custom_preset,
)
from generator import save_locustfile
from runner import LocustRunner

# Default configuration constants
# Target Environment Endpoints & Tokens
EC2_ALB_HOST = "http://campushub-baseline-alb-684305638.ap-south-1.elb.amazonaws.com/"
LAMBDA_API_HOST = "https://5hd795r6zd.execute-api.ap-south-1.amazonaws.com/"
LOCALHOST_HOST = "http://localhost:8000/"

EC2_TOKEN = (
    "<PUT EC2 COGNITO TOKEN HERE>"
)

LAMBDA_TOKEN = (
    "<PUT LAMBDA COGNITO TOKEN HERE>"
)

DEFAULT_HOST = EC2_ALB_HOST
DEFAULT_TOKEN = EC2_TOKEN

CLEANUP_SQL = """-- =============================================================================
-- CampusHub RDS Artifacts Cleanup Script
-- Run this in psql / DBeaver to clean up simulated test items created by Locust.
-- =============================================================================

BEGIN;

-- 1. Clean up listings child references
DELETE FROM listing_watches 
 WHERE listing_id IN (SELECT id FROM listings WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%');

DELETE FROM listing_photos 
 WHERE listing_id IN (SELECT id FROM listings WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%');

DELETE FROM reports 
 WHERE listing_id IN (SELECT id FROM listings WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%');

DELETE FROM notifications 
 WHERE payload::text LIKE '%LoadTest%' OR payload::text LIKE '%[LOAD_TEST]%';

-- 2. Delete the load test listings
DELETE FROM listings 
 WHERE title LIKE '%LoadTest%' OR title LIKE '%[LOAD_TEST]%' OR description LIKE '%Locust%';

-- 3. Delete any test wanted posts, lost/found reports, and interview experiences
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
"""


class CampusHubPerfApp(tk.Tk):
    """Main Application Window."""

    def __init__(self):
        super().__init__()
        self.title("CampusHub - Locust Automated Benchmark Suite (DS252)")
        self.geometry("1280x880")
        self.minsize(1050, 720)

        # Style configuration
        self.style = ttk.Style(self)
        try:
            self.style.theme_use("clam")
        except Exception:
            pass

        self._configure_styles()

        # State tracking
        self.runner: Optional[LocustRunner] = None
        self.current_output_dir: Optional[str] = None
        self.endpoint_vars: Dict[str, tk.BooleanVar] = {}
        self.endpoint_weights: Dict[str, tk.IntVar] = {}
        self.endpoint_widgets: Dict[str, Dict[str, Any]] = {}
        self.module_header_vars: Dict[str, tk.BooleanVar] = {}
        self.token_is_valid = False

        self._create_layout()
        self._load_initial_preset()
        self._validate_token_quiet()

    def _configure_styles(self):
        """Define ttk styles and colors."""
        self.style.configure("Header.TLabel", font=("Helvetica", 14, "bold"))
        self.style.configure("SubHeader.TLabel", font=("Helvetica", 10, "bold"), foreground="#333333")
        self.style.configure("Card.TLabelframe", padding=10)
        self.style.configure("Card.TLabelframe.Label", font=("Helvetica", 10, "bold"), foreground="#1a365d")
        self.style.configure("Green.TButton", font=("Helvetica", 10, "bold"), foreground="#ffffff", background="#2e7d32")
        self.style.map("Green.TButton", background=[("active", "#1b5e20")])
        self.style.configure("Red.TButton", font=("Helvetica", 10, "bold"), foreground="#ffffff", background="#c62828")
        self.style.map("Red.TButton", background=[("active", "#b71c1c")])
        self.style.configure("Accent.TButton", font=("Helvetica", 9, "bold"))

    def _create_layout(self):
        """Construct application panels and notebook tabs."""
        # Main vertical split
        main_paned = ttk.PanedWindow(self, orient=tk.HORIZONTAL)
        main_paned.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        # Left Control Panel (Fixed width options)
        left_frame = ttk.Frame(main_paned, width=440)
        main_paned.add(left_frame, weight=0)

        # Right Content Notebook (Tabs: Endpoints, Dashboard, Logs, SQL)
        right_frame = ttk.Frame(main_paned)
        main_paned.add(right_frame, weight=1)

        self._build_left_panel(left_frame)
        self._build_right_notebook(right_frame)

    def _build_left_panel(self, parent: ttk.Frame):
        """Build target host, auth credentials, presets, and locust controls."""
        canvas = tk.Canvas(parent, borderwidth=0, highlightthickness=0)
        scrollbar = ttk.Scrollbar(parent, orient=tk.VERTICAL, command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # 1. Host Target Card
        host_card = ttk.LabelFrame(scrollable_frame, text="1. Target Host", style="Card.TLabelframe")
        host_card.pack(fill=tk.X, padx=4, pady=5)

        self.host_var = tk.StringVar(value=DEFAULT_HOST)
        host_entry = ttk.Entry(host_card, textvariable=self.host_var, font=("Consolas", 9))
        host_entry.pack(fill=tk.X, pady=3)

        host_btn_row = ttk.Frame(host_card)
        host_btn_row.pack(fill=tk.X, pady=2)
        ttk.Button(host_btn_row, text="EC2 Baseline (ALB)", style="Accent.TButton", command=self.switch_to_ec2).pack(side=tk.LEFT, padx=2)
        ttk.Button(host_btn_row, text="Lambda (API Gateway)", style="Accent.TButton", command=self.switch_to_lambda).pack(side=tk.LEFT, padx=2)
        ttk.Button(host_btn_row, text="Localhost:8000", command=lambda: self.host_var.set(LOCALHOST_HOST)).pack(side=tk.LEFT, padx=2)

        # 2. Authentication & Cognito Token Card
        auth_card = ttk.LabelFrame(scrollable_frame, text="2. Cognito Auth Token", style="Card.TLabelframe")
        auth_card.pack(fill=tk.X, padx=4, pady=5)

        ttk.Label(auth_card, text="JWT Token (accepts raw or 'Bearer <token>'):").pack(anchor=tk.W)
        self.token_text = scrolledtext.ScrolledText(auth_card, height=4, font=("Consolas", 8), wrap=tk.CHAR)
        self.token_text.insert("1.0", DEFAULT_TOKEN)
        self.token_text.pack(fill=tk.X, pady=3)
        self.token_text.bind("<KeyRelease>", lambda e: self._on_token_edited())

        token_btn_row = ttk.Frame(auth_card)
        token_btn_row.pack(fill=tk.X, pady=3)
        self.verify_btn = ttk.Button(token_btn_row, text="Verify Token Live", style="Accent.TButton", command=self.verify_token_live)
        self.verify_btn.pack(side=tk.LEFT, padx=2)
        ttk.Button(token_btn_row, text="Paste EC2 Token", command=lambda: self.set_token_direct(EC2_TOKEN)).pack(side=tk.LEFT, padx=2)
        ttk.Button(token_btn_row, text="Paste Lambda Token", command=lambda: self.set_token_direct(LAMBDA_TOKEN)).pack(side=tk.LEFT, padx=2)
        ttk.Button(token_btn_row, text="Sanitize", command=self.sanitize_token_box).pack(side=tk.LEFT, padx=2)
        ttk.Button(token_btn_row, text="Clear", command=self.clear_token_box).pack(side=tk.LEFT, padx=2)

        # Token status indicator
        self.token_status_lbl = ttk.Label(auth_card, text="Checking token...", font=("Helvetica", 9))
        self.token_status_lbl.pack(anchor=tk.W, pady=2)

        # 3. Presets & Filters Card
        preset_card = ttk.LabelFrame(scrollable_frame, text="3. Preset Profiles & Filters", style="Card.TLabelframe")
        preset_card.pack(fill=tk.X, padx=4, pady=5)

        self.preset_combo_var = tk.StringVar()
        self.preset_combo = ttk.Combobox(preset_card, textvariable=self.preset_combo_var, state="readonly")
        self._refresh_preset_dropdown()
        self.preset_combo.pack(fill=tk.X, pady=3)
        self.preset_combo.bind("<<ComboboxSelected>>", lambda e: self.apply_selected_preset())

        preset_btn_row = ttk.Frame(preset_card)
        preset_btn_row.pack(fill=tk.X, pady=2)
        ttk.Button(preset_btn_row, text="Save Preset", command=self.save_custom_preset_dialog).pack(side=tk.LEFT, padx=2)
        ttk.Button(preset_btn_row, text="Delete Preset", command=self.delete_custom_preset_dialog).pack(side=tk.LEFT, padx=2)

        filter_row = ttk.Frame(preset_card)
        filter_row.pack(fill=tk.X, pady=4)
        ttk.Button(filter_row, text="All Reads", command=self.filter_reads_only).pack(side=tk.LEFT, padx=2)
        ttk.Button(filter_row, text="All Writes", command=self.filter_writes_only).pack(side=tk.LEFT, padx=2)
        ttk.Button(filter_row, text="Select All", command=self.select_all_endpoints).pack(side=tk.LEFT, padx=2)
        ttk.Button(filter_row, text="Clear All", command=self.deselect_all_endpoints).pack(side=tk.LEFT, padx=2)

        # 4. Locust Execution Parameters Card
        locust_card = ttk.LabelFrame(scrollable_frame, text="4. Locust Engine Parameters", style="Card.TLabelframe")
        locust_card.pack(fill=tk.X, padx=4, pady=5)

        # Run Title
        ttk.Label(locust_card, text="Benchmark Run Name:").pack(anchor=tk.W)
        self.run_name_var = tk.StringVar(value="baseline_ec2_run")
        ttk.Entry(locust_card, textvariable=self.run_name_var).pack(fill=tk.X, pady=2)

        # Users and Ramp
        row1 = ttk.Frame(locust_card)
        row1.pack(fill=tk.X, pady=2)
        ttk.Label(row1, text="Peak Users (-u):", width=18).pack(side=tk.LEFT)
        self.users_var = tk.IntVar(value=50)
        ttk.Spinbox(row1, from_=1, to=2000, textvariable=self.users_var, width=10).pack(side=tk.LEFT)

        row2 = ttk.Frame(locust_card)
        row2.pack(fill=tk.X, pady=2)
        ttk.Label(row2, text="Spawn Rate (-r):", width=18).pack(side=tk.LEFT)
        self.spawn_rate_var = tk.DoubleVar(value=10.0)
        ttk.Spinbox(row2, from_=0.5, to=500.0, increment=1.0, textvariable=self.spawn_rate_var, width=10).pack(side=tk.LEFT)

        # Duration
        row3 = ttk.Frame(locust_card)
        row3.pack(fill=tk.X, pady=2)
        ttk.Label(row3, text="Duration (-t):", width=18).pack(side=tk.LEFT)
        self.duration_var = tk.StringVar(value="2m")
        ttk.Combobox(row3, textvariable=self.duration_var, values=["30s", "1m", "2m", "5m", "10m", "Unlimited"], width=9).pack(side=tk.LEFT)

        # Multi-core Processes
        self.multicore_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(locust_card, text="Multi-Core Execution (--processes -1)", variable=self.multicore_var).pack(anchor=tk.W, pady=3)

        # 5. Execution Controls Card
        exec_card = ttk.LabelFrame(scrollable_frame, text="5. Execution & Control", style="Card.TLabelframe")
        exec_card.pack(fill=tk.X, padx=4, pady=5)

        self.start_btn = ttk.Button(exec_card, text="▶ START LOAD TEST", style="Green.TButton", command=self.start_load_test)
        self.start_btn.pack(fill=tk.X, pady=4, ipady=4)

        self.stop_btn = ttk.Button(exec_card, text="⏹ STOP TEST", style="Red.TButton", state=tk.DISABLED, command=self.stop_load_test)
        self.stop_btn.pack(fill=tk.X, pady=3)

        action_row = ttk.Frame(exec_card)
        action_row.pack(fill=tk.X, pady=4)
        ttk.Button(action_row, text="Web UI (8089)", command=lambda: webbrowser.open("http://127.0.0.1:8089")).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        ttk.Button(action_row, text="Open Output", command=self.open_output_folder).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        ttk.Button(action_row, text="RDS Cleanup SQL", command=self.show_sql_cleanup_modal).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)

    def _build_right_notebook(self, parent: ttk.Frame):
        """Build tabbed views for endpoint selection, live stats, and logs."""
        self.notebook = ttk.Notebook(parent)
        self.notebook.pack(fill=tk.BOTH, expand=True)

        # Tab 1: Endpoints & Weightage Matrix
        tab_endpoints = ttk.Frame(self.notebook)
        self.notebook.add(tab_endpoints, text="API Endpoints & Weights")
        self._build_endpoints_tab(tab_endpoints)

        # Tab 2: Live Performance Dashboard
        tab_dash = ttk.Frame(self.notebook)
        self.notebook.add(tab_dash, text="Live Dashboard & Reports")
        self._build_dashboard_tab(tab_dash)

        # Tab 3: Terminal Console Output
        tab_console = ttk.Frame(self.notebook)
        self.notebook.add(tab_console, text="Execution Log Stream")
        self._build_console_tab(tab_console)

    def _build_endpoints_tab(self, parent: ttk.Frame):
        """Scrollable list of all endpoints organized by module with weights."""
        canvas = tk.Canvas(parent, borderwidth=0, highlightthickness=0)
        scrollbar = ttk.Scrollbar(parent, orient=tk.VERTICAL, command=canvas.yview)
        frame = ttk.Frame(canvas)

        frame.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=4, pady=4)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Group endpoints by module
        endpoints_by_module: Dict[str, List[Endpoint]] = {}
        for mod in MODULES:
            endpoints_by_module[mod["id"]] = []
        for ep in ENDPOINTS:
            endpoints_by_module[ep.module_id].append(ep)

        for mod in MODULES:
            mod_id = mod["id"]
            mod_name = mod["name"]
            mod_eps = endpoints_by_module[mod_id]
            if not mod_eps:
                continue

            mod_card = ttk.LabelFrame(frame, text=f"  {mod_name} ({len(mod_eps)} endpoints)  ", padding=6)
            mod_card.pack(fill=tk.X, expand=True, padx=4, pady=4)

            # Module header row with Select/Deselect All
            hdr_frame = ttk.Frame(mod_card)
            hdr_frame.pack(fill=tk.X, pady=2)

            mod_var = tk.BooleanVar(value=True)
            self.module_header_vars[mod_id] = mod_var
            chk_all = ttk.Checkbutton(
                hdr_frame,
                text="Select / Deselect Module",
                variable=mod_var,
                command=lambda m=mod_id: self._toggle_module_endpoints(m)
            )
            chk_all.pack(side=tk.LEFT)

            # Table Header
            tbl_hdr = ttk.Frame(mod_card)
            tbl_hdr.pack(fill=tk.X, pady=(4, 2))
            ttk.Label(tbl_hdr, text="Method & Endpoint Path", width=42, font=("Helvetica", 9, "bold")).pack(side=tk.LEFT)
            ttk.Label(tbl_hdr, text="Type", width=12, font=("Helvetica", 9, "bold")).pack(side=tk.LEFT)
            ttk.Label(tbl_hdr, text="Weight", width=8, font=("Helvetica", 9, "bold")).pack(side=tk.LEFT)
            ttk.Label(tbl_hdr, text="Description", font=("Helvetica", 9, "bold")).pack(side=tk.LEFT, fill=tk.X, expand=True)

            # Endpoint rows
            for ep in mod_eps:
                row = ttk.Frame(mod_card)
                row.pack(fill=tk.X, pady=1)

                var = tk.BooleanVar(value=True)
                weight_var = tk.IntVar(value=ep.default_weight)
                self.endpoint_vars[ep.id] = var
                self.endpoint_weights[ep.id] = weight_var

                # Checkbox & Name
                chk = ttk.Checkbutton(row, text=ep.name, variable=var, width=38)
                chk.pack(side=tk.LEFT)

                # Badges: Auth / Read / Write
                badge_text = "MUTATING" if ep.is_write else "READ-ONLY"
                if ep.requires_auth:
                    badge_text += " [AUTH]"
                badge_lbl = ttk.Label(row, text=badge_text, width=16, font=("Helvetica", 8))
                badge_lbl.pack(side=tk.LEFT)

                # Weight spinbox
                spn = ttk.Spinbox(row, from_=1, to=100, textvariable=weight_var, width=5)
                spn.pack(side=tk.LEFT, padx=4)

                # Description
                desc_lbl = ttk.Label(row, text=ep.description, font=("Helvetica", 8), foreground="#555555")
                desc_lbl.pack(side=tk.LEFT, fill=tk.X, expand=True)

                self.endpoint_widgets[ep.id] = {
                    "checkbox": chk,
                    "spinbox": spn,
                    "endpoint": ep,
                }

    def _build_dashboard_tab(self, parent: ttk.Frame):
        """Live metric cards, active stats, and report shortcuts."""
        # Top Cards row
        cards_frame = ttk.Frame(parent)
        cards_frame.pack(fill=tk.X, padx=8, pady=8)

        def make_stat_card(parent_frame, title: str, default_val: str):
            f = ttk.LabelFrame(parent_frame, text=title, padding=8)
            f.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=4)
            lbl = ttk.Label(f, text=default_val, font=("Helvetica", 16, "bold"), foreground="#1a365d")
            lbl.pack(anchor=tk.CENTER)
            return lbl

        self.stat_status = make_stat_card(cards_frame, "Status", "Idle")
        self.stat_rps = make_stat_card(cards_frame, "Throughput", "0.0 req/s")
        self.stat_fail = make_stat_card(cards_frame, "Failure Rate", "0.0 %")
        self.stat_p99 = make_stat_card(cards_frame, "p99 Latency", "0 ms")
        self.stat_users = make_stat_card(cards_frame, "Active Users", "0")

        # Action shortcuts
        actions_bar = ttk.Frame(parent)
        actions_bar.pack(fill=tk.X, padx=12, pady=6)
        ttk.Button(actions_bar, text="Open Standalone HTML Report", command=self.open_html_report).pack(side=tk.LEFT, padx=4)
        ttk.Button(actions_bar, text="View Generated Charts Folder", command=self.open_output_folder).pack(side=tk.LEFT, padx=4)
        ttk.Button(actions_bar, text="Locust Web Interface (http://localhost:8089)", command=lambda: webbrowser.open("http://127.0.0.1:8089")).pack(side=tk.LEFT, padx=4)

        # Artifacts info box
        info_frame = ttk.LabelFrame(parent, text="Run Artifacts & Charts Generated", padding=8)
        info_frame.pack(fill=tk.BOTH, expand=True, padx=12, pady=8)

        self.artifacts_box = scrolledtext.ScrolledText(info_frame, height=12, font=("Consolas", 9))
        self.artifacts_box.pack(fill=tk.BOTH, expand=True)
        self.artifacts_box.insert(tk.END, "No benchmark run active yet. Press 'START LOAD TEST' to begin.\n\n"
                                          "Artifacts automatically harvested per run:\n"
                                          "  - report.html (Locust interactive standalone HTML report with ECharts)\n"
                                          "  - chart_throughput_rps.png (High-res RPS & Failures/sec timeline)\n"
                                          "  - chart_response_times.png (p50, p90, p95, p99 latencies timeline)\n"
                                          "  - chart_active_users.png (Simulated user ramp timeline)\n"
                                          "  - chart_dashboard.png (Combined 3-panel dashboard)\n"
                                          "  - locust_stats_stats_history.csv & locust_stats_failures.csv\n"
                                          "  - live_stats.json snapshot\n")

    def _build_console_tab(self, parent: ttk.Frame):
        """Scrolled text console streaming stdout/stderr."""
        top_bar = ttk.Frame(parent)
        top_bar.pack(fill=tk.X, padx=8, pady=4)
        ttk.Button(top_bar, text="Clear Console", command=lambda: self.console_box.delete("1.0", tk.END)).pack(side=tk.LEFT)

        self.console_box = scrolledtext.ScrolledText(parent, font=("Consolas", 9), background="#1e1e1e", foreground="#d4d4d4", wrap=tk.CHAR)
        self.console_box.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)

    # =========================================================================
    # Token Sanitization, Decoding & Verification Logic
    # =========================================================================
    def _get_raw_token(self) -> str:
        return self.token_text.get("1.0", tk.END).strip()

    def switch_to_ec2(self):
        self.host_var.set(EC2_ALB_HOST)
        self.set_token_direct(EC2_TOKEN)

    def switch_to_lambda(self):
        self.host_var.set(LAMBDA_API_HOST)
        self.set_token_direct(LAMBDA_TOKEN)

    def set_token_direct(self, token_str: str):
        self.token_text.delete("1.0", tk.END)
        self.token_text.insert("1.0", token_str)
        self._validate_token_quiet()

    def sanitize_token_box(self):
        clean = sanitize_token(self._get_raw_token())
        self.token_text.delete("1.0", tk.END)
        self.token_text.insert("1.0", clean)
        self._validate_token_quiet()

    def clear_token_box(self):
        self.token_text.delete("1.0", tk.END)
        self._validate_token_quiet()

    def _on_token_edited(self):
        # Debounced or quiet check on typing
        self.after(300, self._validate_token_quiet)

    def _validate_token_quiet(self):
        token = sanitize_token(self._get_raw_token())
        if not token:
            self.token_is_valid = False
            self.token_status_lbl.config(text="No token provided. Auth endpoints locked.", foreground="#d32f2f")
            self._update_auth_endpoint_availability()
            return

        info = decode_jwt(token)
        if not info["valid"]:
            self.token_is_valid = False
            self.token_status_lbl.config(text=f"Invalid JWT: {info['error']}", foreground="#d32f2f")
        elif info["is_expired"]:
            self.token_is_valid = False
            self.token_status_lbl.config(text=f"Token EXPIRED: {info['email']} ({info['time_left_str']})", foreground="#c62828")
        else:
            self.token_is_valid = True
            self.token_status_lbl.config(text=f"Token Valid: {info['email']} ({info['time_left_str']})", foreground="#2e7d32")

        self._update_auth_endpoint_availability()

    def verify_token_live(self):
        """Test token against host `/api/v1/me` live in background thread without freezing GUI."""
        host = self.host_var.get().strip()
        token = sanitize_token(self._get_raw_token())
        if not token:
            messagebox.showwarning("No Token", "Please paste your Cognito ID token first.")
            return

        self.token_status_lbl.config(text="⏳ Pinging live backend /api/v1/me...", foreground="#0288d1")
        if hasattr(self, "verify_btn"):
            self.verify_btn.config(state=tk.DISABLED, text="Verifying...")

        def _bg_check():
            ok, code, msg = test_token_live(host, token)
            def _on_done():
                if hasattr(self, "verify_btn"):
                    self.verify_btn.config(state=tk.NORMAL, text="Verify Token Live")
                if ok:
                    self.token_is_valid = True
                    self.token_status_lbl.config(text=f"✔ {msg}", foreground="#2e7d32")
                else:
                    self.token_is_valid = False
                    self.token_status_lbl.config(text=f"✖ {msg}", foreground="#c62828")
                self._update_auth_endpoint_availability()
            self.after(0, _on_done)

        threading.Thread(target=_bg_check, daemon=True).start()

    def _update_auth_endpoint_availability(self):
        """Enforce requirement: uncheck and lock auth endpoints if token is invalid/expired."""
        for ep_id, widgets in self.endpoint_widgets.items():
            ep: Endpoint = widgets["endpoint"]
            chk: ttk.Checkbutton = widgets["checkbox"]
            var: tk.BooleanVar = self.endpoint_vars[ep_id]

            if ep.requires_auth:
                if not self.token_is_valid:
                    # Uncheck and disable
                    var.set(False)
                    chk.state(["disabled"])
                else:
                    chk.state(["!disabled"])

    # =========================================================================
    # Presets and Endpoint Selection Controls
    # =========================================================================
    def _refresh_preset_dropdown(self):
        defaults = list(get_default_presets().keys())
        customs = list_custom_presets()
        values = defaults + [f"[Custom] {c}" for c in customs]
        self.preset_combo["values"] = values
        if not self.preset_combo_var.get() and defaults:
            self.preset_combo_var.set(defaults[0])

    def _load_initial_preset(self):
        defaults = get_default_presets()
        if "Academic & Placement Hub (Recommended)" in defaults:
            self.preset_combo_var.set("Academic & Placement Hub (Recommended)")
            self.apply_selected_preset()

    def apply_selected_preset(self):
        name = self.preset_combo_var.get()
        if not name:
            return

        defaults = get_default_presets()
        if name in defaults:
            config = defaults[name]
        elif name.startswith("[Custom] "):
            clean_name = name[9:]
            config = load_custom_preset(clean_name)
        else:
            return

        ep_weights = config.get("endpoints", {})

        # Apply endpoint selections and weights
        for ep_id, var in self.endpoint_vars.items():
            if ep_id in ep_weights:
                var.set(True)
                self.endpoint_weights[ep_id].set(ep_weights[ep_id])
            else:
                var.set(False)

        # Apply parameters if present
        if "default_users" in config:
            self.users_var.set(config["default_users"])
        if "default_spawn_rate" in config:
            self.spawn_rate_var.set(config["default_spawn_rate"])
        if "default_run_time" in config:
            self.duration_var.set(config["default_run_time"])

        # Enforce auth constraints
        self._update_auth_endpoint_availability()

    def save_custom_preset_dialog(self):
        name = simpledialog.askstring("Save Preset", "Enter a name for this custom benchmark configuration:")
        if not name:
            return

        endpoints_config = {}
        for ep_id, var in self.endpoint_vars.items():
            if var.get():
                endpoints_config[ep_id] = self.endpoint_weights[ep_id].get()

        config = {
            "name": name,
            "created_at": datetime.now().isoformat(),
            "endpoints": endpoints_config,
            "default_users": self.users_var.get(),
            "default_spawn_rate": self.spawn_rate_var.get(),
            "default_run_time": self.duration_var.get(),
        }

        saved_name = save_custom_preset(name, config)
        self._refresh_preset_dropdown()
        self.preset_combo_var.set(f"[Custom] {saved_name}")
        messagebox.showinfo("Saved", f"Custom preset '{saved_name}' saved successfully.")

    def delete_custom_preset_dialog(self):
        current = self.preset_combo_var.get()
        if not current.startswith("[Custom] "):
            messagebox.showwarning("Built-in Preset", "You cannot delete built-in standard presets.")
            return

        clean_name = current[9:]
        if messagebox.askyesno("Confirm Delete", f"Are you sure you want to delete preset '{clean_name}'?"):
            delete_custom_preset(clean_name)
            self._refresh_preset_dropdown()
            self.apply_selected_preset()

    def _toggle_module_endpoints(self, module_id: str):
        state = self.module_header_vars[module_id].get()
        for ep in ENDPOINTS:
            if ep.module_id == module_id:
                if ep.requires_auth and not self.token_is_valid:
                    self.endpoint_vars[ep.id].set(False)
                else:
                    self.endpoint_vars[ep.id].set(state)

    def select_all_endpoints(self):
        for ep in ENDPOINTS:
            if ep.requires_auth and not self.token_is_valid:
                self.endpoint_vars[ep.id].set(False)
            else:
                self.endpoint_vars[ep.id].set(True)

    def deselect_all_endpoints(self):
        for var in self.endpoint_vars.values():
            var.set(False)

    def filter_reads_only(self):
        for ep in ENDPOINTS:
            if ep.is_write:
                self.endpoint_vars[ep.id].set(False)
            else:
                if ep.requires_auth and not self.token_is_valid:
                    self.endpoint_vars[ep.id].set(False)
                else:
                    self.endpoint_vars[ep.id].set(True)

    def filter_writes_only(self):
        for ep in ENDPOINTS:
            if not ep.is_write:
                self.endpoint_vars[ep.id].set(False)
            else:
                if ep.requires_auth and not self.token_is_valid:
                    self.endpoint_vars[ep.id].set(False)
                else:
                    self.endpoint_vars[ep.id].set(True)

    # =========================================================================
    # Test Execution & Realtime Lifecycle
    # =========================================================================
    def start_load_test(self):
        """Prepare folder, generate custom locustfile, and spawn Locust."""
        if self.runner and self.runner.is_running:
            messagebox.showwarning("Already Running", "A Locust test is already active.")
            return

        # Validate selected endpoints
        selected = [ep_id for ep_id, var in self.endpoint_vars.items() if var.get()]
        if not selected:
            messagebox.showerror("No Endpoints", "Please select at least one API endpoint to test.")
            return

        host = self.host_var.get().strip()
        if not host:
            messagebox.showerror("No Host", "Please provide a valid target host link.")
            return

        token = sanitize_token(self._get_raw_token())
        # Check if auth required endpoints are selected
        auth_selected = [ep_id for ep_id in selected if ENDPOINTS_MAP[ep_id].requires_auth]
        if auth_selected and not self.token_is_valid:
            if not messagebox.askyesno(
                "Unvalidated Token",
                f"You have selected {len(auth_selected)} auth-required endpoints, but your token "
                f"is unverified or expired. Requests may result in 401 Unauthorized errors.\n\n"
                f"Proceed anyway?"
            ):
                return

        # Check token expiration against configured test duration
        duration_val = self.duration_var.get().strip().lower()
        duration_sec = 0
        if duration_val.endswith("s"):
            try: duration_sec = int(duration_val[:-1])
            except Exception: pass
        elif duration_val.endswith("m"):
            try: duration_sec = int(duration_val[:-1]) * 60
            except Exception: pass
        elif duration_val.endswith("h"):
            try: duration_sec = int(duration_val[:-1]) * 3600
            except Exception: pass

        if token:
            info = decode_jwt(token)
            rem = info.get("remaining_seconds")
            if rem is not None and duration_sec > 0 and rem < duration_sec:
                time_str = info.get("time_left_str", "soon")
                if not messagebox.askyesno(
                    "Token Expiration Warning",
                    f"⚠️ WARNING: Your Cognito token expires in {time_str},\n"
                    f"but the load test duration is set to {self.duration_var.get()} ({duration_sec}s)!\n\n"
                    f"After expiration, the backend will return 401 Unauthorized for all requests.\n\n"
                    f"Do you want to proceed anyway?"
                ):
                    return

        # Prepare unique run output folder
        # Format: <user_run_name>_<timestamp>_<users>u_<ramp>r_<duration>
        run_name = "".join(c for c in self.run_name_var.get() if c.isalnum() or c in ("-", "_")).strip() or "run"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        users = self.users_var.get()
        ramp = int(self.spawn_rate_var.get())
        duration = self.duration_var.get().strip().replace(" ", "")

        folder_name = f"{run_name}_{timestamp}_{users}u_{ramp}r_{duration}"
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        output_dir = os.path.join(base_dir, "output", folder_name)
        os.makedirs(output_dir, exist_ok=True)
        self.current_output_dir = output_dir

        # Generate custom locustfile inside run folder for reproducibility
        locustfile_path = os.path.join(output_dir, "run_locustfile.py")
        weights = {ep_id: self.endpoint_weights[ep_id].get() for ep_id in selected}
        save_locustfile(locustfile_path, selected, weights, token)

        # Update UI state
        self.start_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL)
        self.stat_status.config(text="Starting...", foreground="#e65100")
        self.notebook.select(1)  # Switch to Dashboard tab

        # Instantiate runner
        processes = -1 if self.multicore_var.get() else 1
        self.runner = LocustRunner(
            locustfile_path=locustfile_path,
            host=host,
            output_dir=output_dir,
            users=users,
            spawn_rate=self.spawn_rate_var.get(),
            run_time=duration,
            processes=processes,
            web_port=8089,
            run_title=f"{run_name} ({users} users, ramp {ramp}/s)",
            log_callback=self._append_console_log,
            metrics_callback=self._update_live_dashboard,
            on_finish_callback=self._on_test_finished,
        )

        self._append_console_log(f"==================================================")
        self._append_console_log(f"Launching Locust Test Run: {folder_name}")
        self._append_console_log(f"Target Host: {host}")
        self._append_console_log(f"Selected Endpoints: {len(selected)}")
        self._append_console_log(f"==================================================")

        self.runner.start(open_browser=True)

    def stop_load_test(self):
        if self.runner and self.runner.is_running:
            self.stop_btn.config(state=tk.DISABLED)
            self.stat_status.config(text="Stopping...", foreground="#c62828")
            threading.Thread(target=self.runner.stop, daemon=True).start()

    def _on_test_finished(self, exit_code: int):
        self.start_btn.config(state=tk.NORMAL)
        self.stop_btn.config(state=tk.DISABLED)
        self.stat_status.config(text="Finished", foreground="#2e7d32")

        self._append_console_log(f"\n[Done] Test run completed. Artifacts stored in:")
        self._append_console_log(f"  {self.current_output_dir}")

        self._update_artifacts_summary()

    def _append_console_log(self, text: str):
        def _append():
            self.console_box.insert(tk.END, text + "\n")
            self.console_box.see(tk.END)
        self.after(0, _append)

    def _update_live_dashboard(self, metrics: Dict[str, Any]):
        def _update():
            state = metrics.get("state", "running").capitalize()
            self.stat_status.config(text=state, foreground="#0288d1" if state == "Running" else "#2e7d32")
            self.stat_rps.config(text=f"{metrics.get('current_rps', 0.0):.1f} req/s")
            
            fail_pct = metrics.get("fail_ratio", 0.0) * 100.0
            fail_color = "#2e7d32" if fail_pct < 1.0 else ("#f57c00" if fail_pct < 5.0 else "#c62828")
            self.stat_fail.config(text=f"{fail_pct:.1f} %", foreground=fail_color)

            p99 = metrics.get("p99_response_time", 0.0)
            self.stat_p99.config(text=f"{int(p99)} ms")
            self.stat_users.config(text=str(metrics.get("user_count", 0)))

            self._update_artifacts_summary()
        self.after(0, _update)

    def _update_artifacts_summary(self):
        if not self.current_output_dir or not os.path.exists(self.current_output_dir):
            return

        files = os.listdir(self.current_output_dir)
        summary = f"Run Directory: {self.current_output_dir}\n"
        summary += f"Files Generated ({len(files)} total):\n"
        for f in sorted(files):
            size = os.path.getsize(os.path.join(self.current_output_dir, f))
            summary += f"  - {f:32} ({size:,} bytes)\n"

        self.artifacts_box.delete("1.0", tk.END)
        self.artifacts_box.insert(tk.END, summary)

    def open_output_folder(self):
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        target = self.current_output_dir if (self.current_output_dir and os.path.exists(self.current_output_dir)) else os.path.join(base_dir, "output")
        os.makedirs(target, exist_ok=True)
        try:
            subprocess.Popen(["xdg-open", target])
        except Exception:
            webbrowser.open(f"file://{target}")

    def open_html_report(self):
        if self.current_output_dir:
            html_path = os.path.join(self.current_output_dir, "report.html")
            if os.path.exists(html_path):
                webbrowser.open(f"file://{html_path}")
                return
        messagebox.showinfo("HTML Report", "Locust HTML report will be available once the test is started and polled.")

    def show_sql_cleanup_modal(self):
        win = tk.Toplevel(self)
        win.title("RDS Test Artifacts Cleanup SQL")
        win.geometry("760x520")

        lbl = ttk.Label(win, text="SQL Command to Remove [LOAD_TEST] Records from PostgreSQL RDS:", font=("Helvetica", 10, "bold"))
        lbl.pack(padx=10, pady=8, anchor=tk.W)

        txt = scrolledtext.ScrolledText(win, font=("Consolas", 9), wrap=tk.NONE)
        txt.insert("1.0", CLEANUP_SQL)
        txt.pack(fill=tk.BOTH, expand=True, padx=10, pady=4)

        btn_row = ttk.Frame(win)
        btn_row.pack(fill=tk.X, padx=10, pady=8)

        def copy_to_clipboard():
            self.clipboard_clear()
            self.clipboard_append(CLEANUP_SQL)
            messagebox.showinfo("Copied", "Cleanup SQL script copied to clipboard!")

        ttk.Button(btn_row, text="Copy SQL to Clipboard", style="Accent.TButton", command=copy_to_clipboard).pack(side=tk.LEFT)
        ttk.Button(btn_row, text="Close", command=win.destroy).pack(side=tk.RIGHT)


if __name__ == "__main__":
    app = CampusHubPerfApp()
    app.mainloop()
