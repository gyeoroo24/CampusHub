#!/usr/bin/env bash
# Creates the Web Push (VAPID) key pair in SSM Parameter Store, once per environment (FR-22):
#   /campushub/<env>/push/vapid_private_key   SecureString, read only by the push-sender Lambda
#   /campushub/<env>/push/vapid_public_key    String, read by the API and handed to browsers
# Safe to run again: existing keys are kept (replacing them would silently break every browser's
# subscription; to rotate on purpose, delete both parameters first, and people turn push on again).
#
#   ./scripts/create_vapid_keys.sh            # environment "dev"
#   ./scripts/create_vapid_keys.sh prod
#
# Needs: aws CLI with access to the account; python3 with `cryptography` (backend/.venv has it).
set -euo pipefail
ENVIRONMENT="${1:-dev}"
PRIVATE="/campushub/$ENVIRONMENT/push/vapid_private_key"
PUBLIC="/campushub/$ENVIRONMENT/push/vapid_public_key"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON="$REPO_DIR/backend/.venv/bin/python"
[ -x "$PYTHON" ] || PYTHON=python3

if aws ssm get-parameter --name "$PRIVATE" >/dev/null 2>&1; then
  echo "VAPID keys already exist at $PRIVATE; nothing to do."
  exit 0
fi

KEYS="$("$PYTHON" -I -c '
import base64
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
key = ec.generate_private_key(ec.SECP256R1())
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
print(b64(key.private_numbers().private_value.to_bytes(32, "big")),
      b64(key.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)))
')"
read -r PRIVATE_KEY PUBLIC_KEY <<<"$KEYS"

aws ssm put-parameter --name "$PRIVATE" --type SecureString --value "$PRIVATE_KEY" \
  --description "CampusHub Web Push VAPID private key (push-sender Lambda only)" >/dev/null
aws ssm put-parameter --name "$PUBLIC" --type String --value "$PUBLIC_KEY" \
  --description "CampusHub Web Push VAPID public key (browsers' applicationServerKey)" >/dev/null
echo "Created $PRIVATE and $PUBLIC."
