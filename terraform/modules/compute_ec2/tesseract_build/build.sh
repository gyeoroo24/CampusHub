#!/usr/bin/env bash
# Builds tesseract-ec2.zip: tesseract, libtesseract/libleptonica and eng+osd tessdata, built for the EC2
# baseline's actual AMI (Amazon Linux 2023, arm64 for the default t4g.* instance types). This is a
# separate build from ../../compute/tesseract_layer (which targets Lambda's x86_64/amazonlinux:2
# runtime) -- the two environments differ in both OS and, by default, CPU architecture, so one zip
# cannot serve both. Needs Docker; it runs inside amazonlinux:2023 so the binaries match the AMI exactly.
# Pass --platform to cross-build for x86_64 instances (t3.*): ./build.sh --platform linux/amd64
#
#   ./build.sh                        -> arm64 (matches the default t4g.* instance_type)
#   ./build.sh --platform linux/amd64 -> x86_64 (for ec2_instance_type = "t3.*" etc.)
set -euo pipefail
PLATFORM="linux/arm64"
if [ "${1:-}" = "--platform" ]; then PLATFORM="$2"; fi

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../tesseract-layer.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/inside.sh" "$WORK/inside.sh"
docker run --rm --platform "$PLATFORM" -v "$WORK:/work" amazonlinux:2023 bash /work/inside.sh
mv "$WORK/tesseract-ec2.zip" "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1)) for $PLATFORM"
