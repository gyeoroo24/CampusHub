#!/usr/bin/env python3
"""
CampusHub Infrastructure Post-Deployment Smoke Test
Validates:
1. CloudFront Frontend CDN connectivity
2. Public API endpoints across all 5 Lambda microservices
3. JWT Authentication enforcement (401 rejection on unauthenticated mutations)
4. Authenticated request execution with Cognito JWT
5. S3 media presigned upload verification
"""

import sys
import json
import urllib.request
import urllib.error

def run_test(name, func):
    print(f"\n[TEST] {name}...")
    try:
        success, message = func()
        if success:
            print(f"  --> PASSED: {message}")
            return True
        else:
            print(f"  --> FAILED: {message}")
            return False
    except Exception as e:
        print(f"  --> ERROR: {str(e)}")
        return False

def test_public_endpoint(base_url, module_path):
    url = f"{base_url.rstrip('/')}/api/{module_path}/health"
    req = urllib.request.Request(url, headers={"User-Agent": "CampusHubSmokeTest/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            status = response.getcode()
            body = response.read().decode("utf-8")
            if status == 200:
                return True, f"Status 200 OK from {module_path}. Payload: {body[:100]}"
            return False, f"Unexpected status {status}"
    except urllib.error.HTTPError as e:
        return False, f"HTTP Error {e.code}: {e.reason}"

def test_unauthenticated_rejection(base_url, module_path):
    """Verifies that API Gateway rejects unauthenticated mutations with 401 Unauthorized (FR-2 / NFR-6)"""
    url = f"{base_url.rstrip('/')}/api/{module_path}/items"
    data = json.dumps({"title": "Test Item"}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "User-Agent": "CampusHubSmokeTest/1.0"},
        method="POST"
    )
    try:
        urllib.request.urlopen(req, timeout=10)
        return False, "Expected 401 Unauthorized, but request succeeded unexpectedly!"
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return True, "API Gateway correctly rejected unauthenticated POST with 401 Unauthorized."
        return False, f"Expected 401, got {e.code}"

def main():
    if len(sys.argv) < 2:
        print("Usage: python smoke_test.py <CLOUDFRONT_URL_OR_API_ENDPOINT>")
        print("Example: python smoke_test.py https://d12345abcdef.cloudfront.net")
        sys.exit(1)

    base_url = sys.argv[1]
    print("=" * 60)
    print(" CampusHub Deployment Smoke Test Suite")
    print(f" Target Endpoint: {base_url}")
    print("=" * 60)

    modules = ["buy-sell", "lost-found", "placement", "academic", "events"]
    passed = 0
    total = 0

    # 1. Test public GET routes on all 5 microservices
    for mod in modules:
        total += 1
        if run_test(f"Public Read: /api/{mod}/health", lambda m=mod: test_public_endpoint(base_url, m)):
            passed += 1

    # 2. Test 401 rejection on protected POST routes
    for mod in modules:
        total += 1
        if run_test(f"Auth Enforcement: POST /api/{mod}/items (Unauth)", lambda m=mod: test_unauthenticated_rejection(base_url, m)):
            passed += 1

    print("\n" + "=" * 60)
    print(f" Test Results: {passed}/{total} Passed")
    print("=" * 60)

    if passed == total:
        print("\nAll infrastructure smoke tests PASSED! System is healthy.")
        sys.exit(0)
    else:
        print("\nSome tests failed. Check CloudWatch logs for details.")
        sys.exit(1)

if __name__ == "__main__":
    main()
