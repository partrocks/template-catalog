#!/bin/sh
set -e

# Allow running composer as root inside container
export COMPOSER_ALLOW_SUPERUSER=1

# Bootstrap dependencies if needed.
if [ ! -f vendor/autoload.php ] || [ composer.lock -nt vendor/autoload.php ] || [ composer.json -nt vendor/autoload.php ]; then
  echo "[bootstrap] Running composer install..."
  composer install --prefer-dist --no-interaction
fi

# Handle JWT keys when Lexik JWT bundle is installed.
if php bin/console list --raw 2>/dev/null | grep -q '^lexik:jwt:generate-keypair$'; then
  mkdir -p config/jwt

  if [ "${APP_ENV:-dev}" = "prod" ]; then
    # Never trust keys baked into images. In prod we require runtime-provided PEM keys.
    rm -f config/jwt/private.pem config/jwt/public.pem

    if [ -n "${JWT_PRIVATE_KEY_PEM:-}" ] && [ -n "${JWT_PUBLIC_KEY_PEM:-}" ]; then
      echo "[bootstrap] Writing JWT keypair from runtime secrets..."
      printf '%s\n' "$JWT_PRIVATE_KEY_PEM" > config/jwt/private.pem
      printf '%s\n' "$JWT_PUBLIC_KEY_PEM" > config/jwt/public.pem
      chmod 600 config/jwt/private.pem config/jwt/public.pem
      chown -R www-data:www-data config/jwt 2>/dev/null || true
    else
      echo "[bootstrap] ERROR: APP_ENV=prod requires JWT_PRIVATE_KEY_PEM and JWT_PUBLIC_KEY_PEM."
      exit 1
    fi
  elif [ ! -f config/jwt/private.pem ] || [ ! -f config/jwt/public.pem ]; then
    echo "[bootstrap] Generating JWT keypair for non-prod..."
    php bin/console lexik:jwt:generate-keypair --skip-if-exists --no-interaction
  fi
else
  echo "[bootstrap] Lexik JWT command not available; skipping key generation."
fi

# Clear Symfony cache at container start to ensure runtime consistency.
echo "[bootstrap] Clearing Symfony cache..."
php bin/console cache:clear --no-interaction || true

exec "$@"