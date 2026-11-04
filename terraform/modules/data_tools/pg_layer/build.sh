#!/usr/bin/env bash
# Builds pg-layer.zip: the PostgreSQL 16 client programs (pg_dump, pg_restore, psql) and the libraries
# they need, as an AWS Lambda layer for x86_64. The data-tools function uses them to export and restore
# the CampusHub database inside the VPC. Needs Docker; it runs inside amazonlinux:2 so the binaries
# match Lambda's operating system. Takes a few minutes.
#
#   ./build.sh   -> writes pg-layer.zip next to this script
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/pg-layer.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/inside.sh" "$WORK/inside.sh"
docker run --rm --platform linux/amd64 -v "$WORK:/work" amazonlinux:2 bash /work/inside.sh
mv "$WORK/pg-layer.zip" "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
