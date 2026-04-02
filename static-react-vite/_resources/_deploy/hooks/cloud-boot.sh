#!/usr/bin/env sh
set -eu
# Cloud boot script is required for `boot.script` in environments.yaml. ALB→EC2 uses platform-generated
# UserData (S3 handoff + http.server); this hook is not executed on that path.
exit 0
