#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

php bin/console doctrine:database:create --if-not-exists --no-interaction || true
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || true
php bin/console cache:clear --no-interaction || true
php bin/console cache:warmup --no-interaction || true

exec frankenphp run --config /app/docker/frankenphp/Caddyfile
