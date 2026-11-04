#!/usr/bin/env bash
# Copies this deployment's live data into terraform/data/snapshot/:
#   campushub.dump   the database (pg_dump, custom format), taken inside the VPC by the data-tools function
#   uploads/         every file in the media bucket except _snapshots/ and _layers/
#   MANIFEST.txt     when it was taken and the row counts of the main tables
#
#   ./scripts/snapshot_export.sh
#
# Snapshot files contain personal data (names, IISc emails, phone numbers). Keep them out of git and
# share them only with people who should see them.
set -euo pipefail
TF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="$TF_DIR/data/snapshot"
cd "$TF_DIR"
FUNCTION="${FUNCTION:-$(terraform output -raw data_tools_function_name)}"
BUCKET="${BUCKET:-$(terraform output -raw media_s3_bucket)}"
mkdir -p "$SNAP"

echo '{"action":"export"}' > "$SNAP/.payload.json"
aws lambda invoke --function-name "$FUNCTION" --cli-read-timeout 900 --payload fileb://"$SNAP/.payload.json" "$SNAP/.export.json" >/dev/null
KEY="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r.get("key") or r.get("errorMessage","error"))' "$SNAP/.export.json")"
if [[ "$KEY" == error* ]] || ! aws s3api head-object --bucket "$BUCKET" --key "$KEY" >/dev/null 2>&1; then
  echo "export failed: $(cat "$SNAP/.export.json")" >&2; exit 1
fi
aws s3 cp "s3://$BUCKET/$KEY" "$SNAP/campushub.dump" --only-show-errors

aws s3 sync "s3://$BUCKET/" "$SNAP/uploads/" --exclude "_snapshots/*" --exclude "_layers/*" --only-show-errors

echo '{"action":"counts"}' > "$SNAP/.payload.json"
aws lambda invoke --function-name "$FUNCTION" --cli-read-timeout 300 --payload fileb://"$SNAP/.payload.json" "$SNAP/.counts.json" >/dev/null
{
  echo "exported: $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo "source bucket: $BUCKET"
  echo "code commit: $(git -C "$TF_DIR/.." rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "row counts:"
  python3 -c 'import json,sys; [print(f"  {k}: {v}") for k,v in json.load(open(sys.argv[1])).items()]' "$SNAP/.counts.json"
  echo "uploads: $(find "$SNAP/uploads" -type f | wc -l | tr -d ' ') files"
} > "$SNAP/MANIFEST.txt"
rm -f "$SNAP/.export.json" "$SNAP/.counts.json" "$SNAP/.payload.json"
# Remove the copy inside the bucket: the snapshot now lives in the local folder.
aws s3 rm "s3://$BUCKET/$KEY" --only-show-errors
cat "$SNAP/MANIFEST.txt"
