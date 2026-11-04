#!/usr/bin/env bash
# Builds tesseract-layer.zip: the Tesseract OCR program and its libraries, English data, and the Python
# packages the mess-menu reader imports (numpy, Pillow, pypdfium2), packaged as an AWS Lambda layer for
# Python 3.11 on x86_64. The reader in backend/app/mess_extract.py runs without it, but then it can't
# read menus from files.
#
# Needs Docker. It builds inside amazonlinux:2 so the binaries match Lambda's operating system; on an
# ARM Mac the build runs under emulation and takes a long time (about 30-60 minutes).
#
#   ./build.sh            -> writes tesseract-layer.zip next to this script
#
# Then point Terraform at it:  tesseract_layer_zip = "modules/compute/tesseract_layer/tesseract-layer.zip"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/tesseract-layer.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/inside.sh" "$WORK/inside.sh"
docker run --rm --platform linux/amd64 -v "$WORK:/work" amazonlinux:2 bash /work/inside.sh
mv "$WORK/tesseract-layer.zip" "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
