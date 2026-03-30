### PartRocks App Template Catalog

## A library of App Templates Curated by PartRocks

> **Syntax reference** — The template-engine that reads these files has its syntax
> definition documented at:
> [partrocks/desktop › template-engine/syntax.md](https://github.com/partrocks/desktop/blob/main/packages/template-engine/syntax.md)

## Custom domains and edge TLS

See [partrocks/desktop › template-engine/template-edge-ssl-contract.md](https://github.com/partrocks/desktop/blob/main/packages/template-engine/template-edge-ssl-contract.md) for required DNS outputs, DigitalOcean `APP_PLATFORM_ID`, and how presets interact with PartRocks domain automation.

## Infra slice taxonomy

Preset `slices` use cross-provider **`sliceKind`** values (v2: `gateway`, `static_site`, `object_storage`, `app_runtime`, `database`, `container_registry`, `edge_binding`, `edge_workload`, `network`) with optional **`shareable: true`** for project-scoped resources. See [partrocks/desktop › template-engine/syntax.md — Infra slices](https://github.com/partrocks/desktop/blob/main/packages/template-engine/syntax.md#infra-slices-provider-native-desired-state).

**Breaking change (taxonomy v2):** existing AWS assets tagged with legacy `partrocks:slice-kind` values (`shareable_resource` / `shareable_gateway`) need redeploy or retag to match desired state.
