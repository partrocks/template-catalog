# Catalog authoring: `preflights.artifacts`

- **`type: default`** — Resolved per provider and the preset’s `app_runtime` slice flavor (see PartRocks desktop repo `docs/internal/artifact-preflights.md`). Prefer this for multi-cloud templates where AWS EC2 should receive a release tarball and DigitalOcean should use the standard App Platform container layout.

- **`type: archive`** — Use when you need a non-root path (`archive.path`), a `buildCommand`, or static handoff without relying on `default` resolution.

- **`type: container_image`** — Use when the app is shipped as a built image (ECR or DOCR). On AWS EC2, pair with `constraints.ec2HandoffLaunchMode: release_container` so the instance runs Docker + your image instead of the S3 static handoff.

- **`type: none`** — Neither image build nor archive snapshot.

For AWS EC2, set **`ec2HandoffLaunchMode`** explicitly when it matters: `static_http` (tarball + Python HTTP server) vs `release_container` (ECR + `docker run`).
