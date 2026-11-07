#!/usr/bin/env bash
# Diagnose CampusHub's actual cloud deployment: which Lambda architecture is really running,
# what commit/image it was built from, what Postgres engine RDS is on, and the real tracebacks
# behind the reported errors (appoint moderator, resolve reports, chat send, chat-key crash).
#
# Read-only — makes no changes. Requires the AWS CLI configured with credentials that can read
# Lambda, RDS and CloudWatch Logs in this account. Run from anywhere; no repo checkout needed
# on the machine that runs this, though you'll want backend_v2 checked out somewhere to compare
# commit timestamps against.
#
# Usage: ./diagnose_cloud_deploy.sh [aws-region]
#   (default region: ap-south-1, per the project's Terraform default)

set -euo pipefail
REGION="${1:-ap-south-1}"

echo "=================================================================="
echo "STEP 0 — Which Lambda architecture is actually deployed?"
echo "=================================================================="
echo "This repo contains TWO different, incompatible backend deployment approaches:"
echo "  (A) a single Docker-image Lambda running the real FastAPI app"
echo "      (backend/Dockerfile.lambda, handler app.main.handler via Mangum) — this is what"
echo "      backend/README.md 'Deploying on AWS' describes, and what all the application code"
echo "      in backend/app/ (moderators.py, reports.py, chat.py, seller_trust.py, ...) is."
echo "  (B) a Terraform-provisioned set of 5 zip-packaged Lambdas"
echo "      (terraform/modules/compute/lambda_src/app.py, handler app.lambda_handler) that is a"
echo "      separate, hand-written ~500-line stub with its own raw Postgres wire-protocol client."
echo "      It only implements basic buy-sell/lost-found/academic-hub/placement-hub/community-"
echo "      events handlers — it has NO moderator-grant, report-resolution, or chat-messaging"
echo "      code at all. If this is what's live, every one of the 4 reported errors is explained"
echo "      immediately: those features simply don't exist in this deployment."
echo "This step tells you which one (or both) is actually in the account right now."
echo

FUNCTIONS=$(aws lambda list-functions --region "$REGION" \
  --query "Functions[?contains(FunctionName, 'campushub')].FunctionName" --output text || true)

if [[ -z "$FUNCTIONS" ]]; then
  echo "No Lambda functions with 'campushub' in the name found in $REGION."
  echo "Check the region/credentials, or list everything with:"
  echo "  aws lambda list-functions --region $REGION --query 'Functions[].FunctionName'"
  exit 1
fi

for FN in $FUNCTIONS; do
  echo "--- $FN ---"
  aws lambda get-function --region "$REGION" --function-name "$FN" \
    --query "{Handler:Configuration.Handler, PackageType:Configuration.PackageType, Runtime:Configuration.Runtime, LastModified:Configuration.LastModified, CodeSha256:Configuration.CodeSha256, ImageUri:Code.ImageUri, MemorySize:Configuration.MemorySize, Timeout:Configuration.Timeout}" \
    --output table
  echo
done

echo "Reading the table(s) above:"
echo "  Handler = app.main.handler, PackageType = Image  -> architecture (A), the real backend."
echo "    Compare LastModified / the image digest against 'git log backend_v2 --date=iso' to see"
echo "    how stale it is relative to HEAD (ae4a744 at the time this script was written)."
echo "  Handler = app.lambda_handler, PackageType = Zip   -> architecture (B), the stub. Stop here"
echo "    and read the comment above again — the fix is deploying the real app, not patching SQL."
echo

echo "=================================================================="
echo "STEP 1 — RDS engine version and identifier"
echo "=================================================================="
aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?contains(DBInstanceIdentifier, 'campushub')].{Id:DBInstanceIdentifier, Engine:Engine, EngineVersion:EngineVersion, Status:DBInstanceStatus, Endpoint:Endpoint.Address}" \
  --output table

echo "schema.sql's uq_mod_active_grant index uses NULLS NOT DISTINCT (line 247-249), which needs"
echo "Postgres 15+. Local dev runs postgres:16.4 and Terraform's db_engine_version default is"
echo "\"16\" — if EngineVersion above is below 15, schema.sql would fail to apply at exactly that"
echo "line, independent of any application code."
echo

echo "=================================================================="
echo "STEP 2 — Real tracebacks from CloudWatch (last 24h, ERROR only)"
echo "=================================================================="
echo "For the clearest result, reproduce each of the 4 failing actions in the live app right"
echo "before running this, so today's actual exception/stack trace shows up below."
echo
for FN in $FUNCTIONS; do
  echo "--- /aws/lambda/$FN ---"
  aws logs tail "/aws/lambda/$FN" --region "$REGION" --since 24h --filter-pattern "ERROR" \
    || echo "(no log group yet, or no ERROR lines in the last 24h)"
  echo
done

echo "=================================================================="
echo "Done. Hand back: the Handler/PackageType line for each function, the EngineVersion, and"
echo "any ERROR tracebacks — that's enough to confirm the real root cause and scope the actual"
echo "fix (see docs/deployment errors resolution.md and the diagnose_cloud_deploy.sql companion"
echo "script for the matching database-side checks)."
echo "=================================================================="
