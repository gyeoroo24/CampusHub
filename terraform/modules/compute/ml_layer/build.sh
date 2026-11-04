#!/usr/bin/env bash
# Builds ml-layer.zip: what category suggestion (backend/app/categories_suggest.py) needs and the API zip
# leaves out (see backend/requirements-lambda-zip.txt) — onnxruntime, tokenizers and numpy under python/,
# and the bge-small-en-v1.5 model (34 MB) under models/. Lambda unzips a layer into /opt, so the functions
# that carry it set CAMPUSHUB_MATCH_MODEL_DIR=/opt/models.
#
# No Docker needed: pip fetches the Linux wheels. Versions are the newest that run on Lambda's Python 3.11
# (Amazon Linux 2, glibc 2.26): later onnxruntime wheels need glibc 2.27+, and onnxruntime 1.16 is built
# against numpy 1.x. About 150 MB unzipped; with the API's own ~75 MB that stays under Lambda's 250 MB.
#
#   ./build.sh   -> writes ml-layer.zip next to this script
#
# Then point Terraform at it:  ml_layer_zip = "modules/compute/ml_layer/ml-layer.zip"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$HERE/../../../../backend"
OUT="$HERE/ml-layer.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PIP=$(command -v pip3 || command -v pip)
PYTHON=$(command -v python3 || command -v python)

"$PIP" install --quiet --no-cache-dir --no-deps --target "$WORK/python" \
  --platform manylinux2014_x86_64 --implementation cp --python-version 3.11 --only-binary=:all: \
  onnxruntime==1.16.3 numpy==1.26.4 tokenizers==0.23.3 \
  flatbuffers==25.12.19 packaging protobuf coloredlogs humanfriendly
find "$WORK/python" -type d -name "__pycache__" -prune -exec rm -rf {} +

"$PYTHON" "$BACKEND/scripts/fetch_match_models.py" "$WORK/models" --suggest-only
rm -rf "$WORK/models/twitter-roberta-sentiment"   # sentiment isn't served from these functions

rm -f "$OUT"
(cd "$WORK" && zip -qr "$OUT" python models)
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
