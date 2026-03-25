# Template contract: DNS targets and deploy-edge TLS automation

PartRocks domain assignment reads **environment outputs** after deploy to (1) build DNS records and (2) optionally drive **deploy-provider** custom hostname / edge TLS APIs (for example DigitalOcean App Platform). Certificate automation for **AWS CloudFront + ACM** stays in the AWS provider and only runs when the DNS target is a CloudFront hostname.

## DNS outputs (required for assignment)

Presets should expose enough data for the platform to create correct zone records.

| Output / convention | Meaning |
| ------------------- | ------- |
| `dns_name` | Legacy-friendly hostname for CNAME/A style targets. |
| `public_url` | Often merged with base URL; may inform previews. |
| Structured targets (when used) | `dnsTargetType`, `dnsTargetValue`, `dnsTargetMeta` on the environment — see the template-engine and platform resolver. |
| `canonical_hosted_zone_id` + alias DNS name | For **Route 53 apex alias** records toward AWS front doors. |

**Route 53 apex:** Alias records toward AWS require DNS name **and** hosted zone id. Edge automation does not remove this constraint; CNAME at zone apex in Route 53 remains invalid.

## Edge automation outputs (deploy provider)

These populate `HostingEdgeBindingContext.resourceRefs` in PartRocks. Keys are normalized in code (`@partrocks/provider-control`).

| Env output key | Maps to `resourceRefs` | Consumer |
| -------------- | ---------------------- | -------- |
| `APP_PLATFORM_ID` | `digitalocean_app_id` | DigitalOcean Apps API: attach custom hostname to the app spec. |
| `digitalocean_app_id` | same | Alternate alias for the same ref. |

## Requirements for automated custom domains

Presets that **support PartRocks custom-domain automation** for DigitalOcean App Platform **must** export `APP_PLATFORM_ID` (OpenTofu output) and include it in **preset `outputs`** so merged environment outputs contain that key (or `digitalocean_app_id`).

Without it, DNS can still be automated, but the desktop will not call the Apps API to register the hostname; operators must add the custom domain in the DigitalOcean UI or extend IaC.

## AWS (certificate / CloudFront)

Templates that front the app with **CloudFront** should expose outputs that resolve to a **CloudFront DNS name** so the AWS provider can run ACM + alias attachment. Non-CloudFront targets skip that path by design (`certificateStatus: not_required`).
