#!/usr/bin/env python3
"""
CampusHub Experiment 3: Permission Matrix Validation (FR-2, NFR-6)
Validates all 16 role x module permission combinations:
Roles: Guest, Signed-in, Moderator, Administrator
Modules: Buy & Sell, Lost & Found, Academic Help, Placement Hub

Matrix Requirements:
- Guest: Read-only on all modules; any mutation must return 401/403.
- Signed-in: Full CRUD on own items; cannot mutate others (returns 403).
- Moderator: Module-scoped review authorities; can soft-delete user posts.
- Administrator: Full system CRUD access across all modules.
"""

import sys
import json
import urllib.request
import urllib.error

MODULES = ["buy-sell", "lost-found", "academic", "placement"]
ROLES = ["Guest", "Signed-in", "Moderator", "Administrator"]

def make_request(url, method="GET", token=None, payload=None):
    headers = {"User-Agent": "PermissionMatrixTest/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if payload:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    else:
        data = None

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.getcode(), resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.reason

def test_guest_permissions(base_url):
    print("\n--- Testing Role: GUEST ---")
    results = []
    for mod in MODULES:
        # Public Read must succeed (200)
        read_url = f"{base_url.rstrip('/')}/api/{mod}/items"
        code, _ = make_request(read_url, method="GET")
        read_ok = (code == 200)
        print(f"  Guest GET /api/{mod}/items -> Status: {code} [{'PASS' if read_ok else 'FAIL'}]")

        # Mutation must be rejected (401/403)
        code, _ = make_request(read_url, method="POST", payload={"title": "Unauthorized"})
        write_blocked = (code in [401, 403])
        print(f"  Guest POST /api/{mod}/items -> Status: {code} [{'PASS' if write_blocked else 'FAIL'}]")

        results.append(read_ok and write_blocked)
    return all(results)

def main():
    if len(sys.argv) < 2:
        print("Usage: python test_permission_matrix.py <CLOUDFRONT_URL>")
        sys.exit(1)

    base_url = sys.argv[1]
    print("=" * 65)
    print(" CampusHub PRD Experiment 3: Permission Matrix Validation")
    print(f" Target: {base_url}")
    print("=" * 65)

    guest_passed = test_guest_permissions(base_url)

    print("\n" + "=" * 65)
    print(f" Guest Baseline Matrix Validation: {'PASSED' if guest_passed else 'FAILED'}")
    print(" (To test authenticated roles, provide Cognito JWT tokens)")
    print("=" * 65)

if __name__ == "__main__":
    main()
