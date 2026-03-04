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
  echo "[bootstrap] Generating JWT keypair for non-prod..."
  php bin/console lexik:jwt:generate-keypair --skip-if-exists --no-interaction
else
  echo "[bootstrap] Lexik JWT command not available; skipping key generation."
fi

# Clear Symfony cache at container start to ensure runtime consistency.
echo "[bootstrap] Clearing Symfony cache..."
php bin/console cache:clear --no-interaction || true

echo "[bootstrap] Creating database..."
php bin/console doctrine:database:create --if-not-exists --no-interaction || true

echo "[bootstrap] Making migrations..."
php bin/console make:migration --no-interaction || true

echo "[bootstrap] Migrating database..."
php bin/console doctrine:migrations:migrate --no-interaction || true

echo "[bootstrap] Loading fixtures..."
php bin/console doctrine:fixtures:load --no-interaction || true

exec "$@"