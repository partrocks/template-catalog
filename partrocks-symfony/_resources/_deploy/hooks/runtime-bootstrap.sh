#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

echo "[bootstrap] starting runtime bootstrap"

# Ensure runtime dirs exist with sane permissions
mkdir -p var/cache var/log

# If you move to RS256 later, support file materialization from secrets:
# - JWT_PRIVATE_KEY (PEM content)
# - JWT_PUBLIC_KEY  (PEM content)
if [ -n "${JWT_PRIVATE_KEY:-}" ] && [ -n "${JWT_PUBLIC_KEY:-}" ]; then
  echo "[bootstrap] materializing JWT key files from env secrets"
  mkdir -p config/jwt
  printf "%s" "$JWT_PRIVATE_KEY" > config/jwt/private.pem
  printf "%s" "$JWT_PUBLIC_KEY"  > config/jwt/public.pem
  chmod 600 config/jwt/private.pem
  chmod 644 config/jwt/public.pem
elif [ -n "${JWT_SECRET_KEY:-}" ]; then
  # Current mode in your Tofu: shared secret style.
  # No file write needed unless your Symfony config explicitly requires PEM files.
  echo "[bootstrap] using JWT_SECRET_KEY from env"
else
  # Optional non-prod fallback only:
  if [ "${ALLOW_EPHEMERAL_JWT_KEYGEN:-false}" = "true" ]; then
    echo "[bootstrap] no JWT env provided, generating ephemeral keypair"
    mkdir -p config/jwt
    php bin/console lexik:jwt:generate-keypair --skip-if-exists --no-interaction || true
  else
    echo "[bootstrap] warning: no JWT secret/key configured"
  fi
fi

echo "[bootstrap] complete"