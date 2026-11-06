#!/usr/bin/env bash
# Builds the Flutter web app for this AWS deployment and publishes it: S3 sync, then a CloudFront
# cache invalidation. Run after `terraform apply`. The build takes the API address and the Cognito
# Hosted UI settings from the Terraform outputs, so nothing is hard-coded to one account.
#
#   ./scripts/deploy_frontend.sh
#
# Needs: terraform (state present in this directory), flutter, aws CLI with access to the account.
set -euo pipefail
TF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$TF_DIR/.." && pwd)"

cd "$TF_DIR"
BUCKET="$(terraform output -raw frontend_s3_bucket)"
CF_DOMAIN="$(terraform output -raw cloudfront_domain_name)"
DIST_ID="$(terraform output -raw cloudfront_distribution_id)"
COGNITO_DOMAIN="$(terraform output -raw cognito_hosted_ui_domain)"
CLIENT_ID="$(terraform output -raw cognito_client_id)"

cd "$REPO_DIR/frontend"
flutter pub get >/dev/null
flutter build web --release \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL="https://$CF_DOMAIN" \
  --dart-define=COGNITO_DOMAIN="$COGNITO_DOMAIN" \
  --dart-define=COGNITO_CLIENT_ID="$CLIENT_ID"

aws s3 sync build/web "s3://$BUCKET/" --delete
# The app's entry files keep their names across builds, so tell browsers to check for a new version on
# every load; without a Cache-Control header they may keep running an old build after a deploy.
for f in index.html flutter_bootstrap.js flutter.js main.dart.js flutter_service_worker.js version.json manifest.json; do
  if [ -f "build/web/$f" ]; then aws s3 cp "build/web/$f" "s3://$BUCKET/$f" --cache-control "no-cache" --only-show-errors; fi
done
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" >/dev/null
echo "published: https://$CF_DOMAIN (cache invalidation started)"
