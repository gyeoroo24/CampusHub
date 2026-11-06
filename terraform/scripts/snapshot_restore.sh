#!/usr/bin/env bash
# Restores terraform/data/snapshot/ into this deployment: the database (replacing its tables) and the
# media bucket's uploads. Run after `terraform apply`, on an empty database.
#
#   ./scripts/snapshot_restore.sh            # refuses if the database already has tables
#   FORCE=1 ./scripts/snapshot_restore.sh    # replaces existing tables
set -euo pipefail
TF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="$TF_DIR/data/snapshot"
cd "$TF_DIR"
[[ -f "$SNAP/campushub.dump" ]] || { echo "no snapshot at $SNAP (run snapshot_export.sh on the source deployment, or copy the folder here)" >&2; exit 1; }
FUNCTION="${FUNCTION:-$(terraform output -raw data_tools_function_name)}"
BUCKET="${BUCKET:-$(terraform output -raw media_s3_bucket)}"
KEY="_snapshots/restore.dump"

aws s3 cp "$SNAP/campushub.dump" "s3://$BUCKET/$KEY" --only-show-errors
FORCE_JSON=$([[ "${FORCE:-0}" == "1" ]] && echo true || echo false)
echo "{\"action\":\"restore\",\"key\":\"$KEY\",\"force\":$FORCE_JSON}" > "$SNAP/.payload.json"
aws lambda invoke --function-name "$FUNCTION" --cli-read-timeout 900 --payload fileb://"$SNAP/.payload.json" "$SNAP/.restore.json" >/dev/null
rm -f "$SNAP/.payload.json"
cat "$SNAP/.restore.json"; echo
rm -f "$SNAP/.restore.json"
aws s3 rm "s3://$BUCKET/$KEY" --only-show-errors

if [[ -d "$SNAP/uploads" ]]; then
  aws s3 sync "$SNAP/uploads/" "s3://$BUCKET/" --only-show-errors
  echo "uploads restored: $(find "$SNAP/uploads" -type f | wc -l | tr -d ' ') files"
fi
