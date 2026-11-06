#!/usr/bin/env bash
# Builds the zip deployment package for the API Lambda: the real FastAPI app (backend/app), plus
# its dependencies (backend/requirements-lambda-zip.txt — a trimmed copy of requirements.txt; see
# that file's header for which packages it leaves out and why). Run by Terraform's null_resource
# in main.tf; not meant to be run by hand, but safe to.
#
# Usage: build_lambda_zip.sh <path-to-backend-dir> <path-to-build-dir>
set -euo pipefail

BACKEND_DIR="$1"
BUILD_DIR="$2"

if ! command -v pip >/dev/null 2>&1 && ! command -v pip3 >/dev/null 2>&1; then
  echo "build_lambda_zip.sh: no pip/pip3 on PATH — install Python/pip on this machine before running terraform apply." >&2
  exit 1
fi
PIP=$(command -v pip3 || command -v pip)

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --platform/--only-binary pulls manylinux wheels for Lambda's runtime, regardless of what OS
# terraform apply itself runs on (e.g. building on a Mac still gets Linux wheels).
"$PIP" install --quiet --no-cache-dir \
  --platform manylinux2014_x86_64 --implementation cp --python-version 3.11 --only-binary=:all: \
  -r "$BACKEND_DIR/requirements-lambda-zip.txt" \
  --target "$BUILD_DIR"

cp -r "$BACKEND_DIR/app" "$BUILD_DIR/app"

# Keep the zip lean: drop bytecode caches, tests and dist-info RECORD/licence bloat.
find "$BUILD_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "$BUILD_DIR" -type d -name "tests" -prune -exec rm -rf {} +
find "$BUILD_DIR" -type d -name "*.dist-info" -exec sh -c 'rm -f "$1"/RECORD "$1"/LICENSE* "$1"/licenses/*' _ {} \; 2>/dev/null || true
