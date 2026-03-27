#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

# Shared JWT / directory setup (same behavior as legacy instance-bootstrap hook).
. /opt/partrocks/hooks/instance-bootstrap.sh

php bin/console doctrine:database:create --if-not-exists --no-interaction || true
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || true
php bin/console cache:warmup --no-interaction || true

exec sh /opt/partrocks/hooks/startup.sh
