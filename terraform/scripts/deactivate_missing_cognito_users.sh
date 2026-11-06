#!/usr/bin/env bash
# Deactivates every user whose sign-in account isn't in this deployment's Cognito user pool, so their
# listings show "Deactivated account" and they can't be messaged. This happens after a snapshot restore:
# the users table comes from another deployment, but that deployment's Cognito accounts don't.
# The admin is never touched. Users who sign up here later get a new row, so nothing needs undoing.
#
#   ./scripts/deactivate_missing_cognito_users.sh            # show who would be deactivated
#   ./scripts/deactivate_missing_cognito_users.sh --apply    # deactivate them
#
# Runs the SQL through the data-tools function (inside the VPC), like the snapshot scripts.
set -euo pipefail
TF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TF_DIR"
FUNCTION="${FUNCTION:-$(terraform output -raw data_tools_function_name)}"
POOL_ID="${POOL_ID:-$(terraform output -raw cognito_user_pool_id)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The pool signs people in by email, so each Cognito username is the user's sub.
aws cognito-idp list-users --user-pool-id "$POOL_ID" --query 'Users[].Username' --output text \
  | tr '\t' '\n' | sed '/^$/d' > "$WORK/subs.txt"
echo "Cognito accounts in $POOL_ID: $(wc -l < "$WORK/subs.txt" | tr -d ' ')"

python3 - "$WORK/subs.txt" "${1:-}" > "$WORK/payload.json" <<'EOF'
import json, sys
subs = [s.strip() for s in open(sys.argv[1]) if s.strip()]
apply = sys.argv[2] == "--apply"
values = ", ".join("('" + s.replace("'", "''") + "')" for s in subs) or "(NULL)"
where = (f"is_active AND base_role <> 'admin' AND cognito_sub NOT IN "
         f"(SELECT sub FROM (VALUES {values}) AS pool(sub) WHERE sub IS NOT NULL)")
sql = f"SELECT email, name FROM users WHERE {where} ORDER BY email;\n"
if apply:
    sql += f"UPDATE users SET is_active = false WHERE {where};\n"
print(json.dumps({"action": "migrate", "sql": sql}))
EOF

aws lambda invoke --function-name "$FUNCTION" --cli-read-timeout 300 \
  --payload fileb://"$WORK/payload.json" "$WORK/out.json" >/dev/null
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r.get("output") or r)' "$WORK/out.json"
[[ "${1:-}" == "--apply" ]] || echo "Dry run. Re-run with --apply to deactivate these users."
