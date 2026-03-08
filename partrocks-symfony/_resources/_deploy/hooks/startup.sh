#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

# Optional startup hooks from lifecycle (if you render these env vars)
# e.g. APP_STARTUP_HOOK_1='php bin/console cache:warmup --no-interaction || true'
i=1
while [ "$i" -le 10 ]; do
  var="APP_STARTUP_HOOK_${i}"
  eval cmd="\${$var:-}"
  if [ -n "${cmd:-}" ]; then
    echo "[startup] running hook $i"
    # shellcheck disable=SC2086
    sh -c "$cmd"
  fi
  i=$((i + 1))
done

# to call a script
# sh /opt/partrocks/hooks/script_from_hooks.sh

APP_RUN_COMMAND="${APP_RUN_COMMAND:-php -S 0.0.0.0:9000 -t public}"


### DEBUGGING
log_env_meta() {
  name="$1"
  eval val="\${$name:-}"
  echo "[startup][debug] ${name}=${val}"
}
echo "[startup][debug] APP_ENV=${APP_ENV:-<unset>}"
log_env_meta "DATABASE_URL"
log_env_meta "APP_SECRET"
log_env_meta "JWT_SECRET_KEY"
### DEBUGGING

echo "[startup] starting app process"
exec sh -c "$APP_RUN_COMMAND"