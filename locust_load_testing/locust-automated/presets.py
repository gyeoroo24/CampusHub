"""Predefined test profiles and custom preset management."""
import os
import json
from typing import Dict, Any, List
from catalog import ENDPOINTS, ENDPOINTS_MAP

PRESETS_DIR = os.path.join(os.path.dirname(__file__), "custom_presets")


def get_default_presets() -> Dict[str, Dict[str, Any]]:
    """Return built-in standard presets."""
    # 1. Minimal (PRD §7 Trace)
    minimal_endpoints = {
        "health": 5,
        "listings_feed": 30,
        "listings_category": 10,
        "listings_search": 10,
        "listings_detail": 10,
        "notifications_inbox": 15,
        "mess_menus": 5,
        "events_feed": 5,
        "create_listing": 10,
    }

    # 2. Academic & Placement Hub Focused Benchmark
    academic_placement_endpoints = {
        "health": 5,
        # Academic Help (50%)
        "academic_departments": 6,
        "department_courses": 8,
        "course_detail": 6,
        "course_feedback": 12,
        "course_my_feedback": 4,
        "course_materials": 4,
        "course_survival_guide": 4,
        "course_forum": 4,
        "follow_course": 2,
        # Placement Hub (45%)
        "placement_companies": 8,
        "company_detail": 4,
        "company_hiring_stats": 4,
        "company_seniors": 4,
        "company_forum": 3,
        "placement_stats": 5,
        "placement_ppts": 4,
        "placement_interviews": 5,
        "interview_detail": 3,
        "create_interview": 2,
    }

    # 3. Comprehensive (All endpoints enabled with catalog defaults)
    comprehensive_endpoints = {ep.id: ep.default_weight for ep in ENDPOINTS}

    # 4. Read-Only (All GET endpoints)
    read_only_endpoints = {ep.id: ep.default_weight for ep in ENDPOINTS if not ep.is_write}

    # 5. Write-Heavy / Creation Benchmark
    write_heavy_endpoints = {ep.id: ep.default_weight for ep in ENDPOINTS if ep.is_write}
    # Add baseline health for reference
    write_heavy_endpoints["health"] = 2

    return {
        "Academic & Placement Hub (Recommended)": {
            "description": "Focused workload on Academic reviews and Placement directory (high cache & throughput)",
            "endpoints": academic_placement_endpoints,
            "default_users": 50,
            "default_spawn_rate": 10,
            "default_run_time": "2m",
        },
        "Comprehensive (All 10 Modules)": {
            "description": "Complete performance harness testing 40+ endpoints across all 10 CampusHub modules",
            "endpoints": comprehensive_endpoints,
            "default_users": 50,
            "default_spawn_rate": 10,
            "default_run_time": "2m",
        },
        "Minimal (PRD §7 Workload)": {
            "description": "PRD Section 7 mixed trace: 60% marketplace reads, 25% status, 15% writes",
            "endpoints": minimal_endpoints,
            "default_users": 50,
            "default_spawn_rate": 10,
            "default_run_time": "1m",
        },
        "Read-Only (All GET Endpoints)": {
            "description": "Safe read-only browsing across all modules (zero DB mutation)",
            "endpoints": read_only_endpoints,
            "default_users": 60,
            "default_spawn_rate": 10,
            "default_run_time": "2m",
        },
        "Write-Heavy (Creation & Mutating)": {
            "description": "Stress-test database write path, locking, and mutation endpoints",
            "endpoints": write_heavy_endpoints,
            "default_users": 20,
            "default_spawn_rate": 5,
            "default_run_time": "1m",
        },
    }


def list_custom_presets() -> List[str]:
    """Return list of custom preset names saved in custom_presets/."""
    if not os.path.exists(PRESETS_DIR):
        return []
    names = []
    for f in os.listdir(PRESETS_DIR):
        if f.endswith(".json"):
            names.append(f[:-5])
    return sorted(names)


def save_custom_preset(name: str, config: Dict[str, Any]) -> str:
    """Save custom configuration to JSON file."""
    os.makedirs(PRESETS_DIR, exist_ok=True)
    # Sanitize filename
    clean_name = "".join(c for c in name if c.isalnum() or c in (" ", "_", "-")).strip()
    if not clean_name:
        clean_name = "custom_preset"
    path = os.path.join(PRESETS_DIR, f"{clean_name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
    return clean_name


def load_custom_preset(name: str) -> Dict[str, Any]:
    """Load custom preset from file."""
    path = os.path.join(PRESETS_DIR, f"{name}.json")
    if not os.path.exists(path):
        raise FileNotFoundError(f"Preset file not found: {path}")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def delete_custom_preset(name: str) -> bool:
    """Delete custom preset."""
    path = os.path.join(PRESETS_DIR, f"{name}.json")
    if os.path.exists(path):
        os.remove(path)
        return True
    return False
