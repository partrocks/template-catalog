# Template contract: DNS targets, deploy outputs, and edge TLS

PartRocks domain assignment reads **environment outputs** after deploy to (1) build DNS records in the user-chosen **DNS provider** (Port A) and (2) drive **hosting / edge TLS** APIs when refs exist (Port B). **Port C** (Let's Encrypt via `@partrocks/cert-engine`) is separate and only used for upload-based edges (for example DigitalOcean load balancers).

Canonical mapping from Terraform/OpenTofu output names to `HostingEdgeBindingContext.resourceRefs` is implemented in `buildHostingEdgeBindingContext` in `@partrocks/provider-control` (source: `packages/provider-control/src/edge-binding-context.ts` in the PartRocks desktop repo). Presets should expose the keys below (via `outputs` / merged env outputs) so automation can run.

## DNS routing outputs (required for assignment)

| Output / convention | Meaning |
| ------------------- | ------- |
| `dns_name` | Hostname for CNAME-style targets (HTTPS prefix stripped). |
| `dnsTargetType` / `dnsTargetValue` / `dnsTargetMeta` | Structured target from the template engine (A, CNAME, or ALIAS with hosted zone id). |
| `canonical_hosted_zone_id` | With `dns_name`, enables **Route 53 apex alias** toward AWS front doors (CloudFront, ALB, etc.). |
| `public_url` | May inform previews; not required for linking. |

**Route 53 apex:** Alias records need DNS name **and** hosted zone id. CNAME at zone apex in Route 53 is invalid.

**Cross-provider DNS:** Validation records (ACM, custom hostname DCV, ACME DNS-01) are always written in the **DNS provider** the user selected for the domain, not necessarily the hosting vendor.

## Edge automation outputs by hosting provider (`resourceRefs`)

These populate after deploy; each row lists accepted **environment output keys** (first match wins per ref).

### AWS (ACM + CloudFront)

| `resourceRefs` key | Accepted output keys | Purpose |
| ------------------ | -------------------- | ------- |
| `aws_cloudfront_distribution_id` | `CLOUDFRONT_DISTRIBUTION_ID`, `cloudfront_distribution_id`, `aws_cloudfront_distribution_id` | Custom alias + TLS attachment on CloudFront. |
| `aws_acm_certificate_arn` | `ACM_CERTIFICATE_ARN`, `acm_certificate_arn`, `aws_acm_certificate_arn`, `certificate_arn` | Optional; often created during linking rather than from IaC. |

**DNS assumptions:** For ACM DNS validation when DNS is Route 53, records are written in the customer's zone via Port A. For Cloudflare DNS, DCV CNAMEs go to Cloudflare the same way.

### DigitalOcean

| `resourceRefs` key | Accepted output keys | Purpose |
| ------------------ | -------------------- | ------- |
| `digitalocean_app_id` | `APP_PLATFORM_ID`, `digitalocean_app_id` | App Platform custom hostname API (managed TLS on DO edge). |
| `digitalocean_load_balancer_id` | `DIGITALOCEAN_LOAD_BALANCER_ID`, `digitalocean_load_balancer_id`, `do_load_balancer_id` | Load balancer custom certificate upload + attachment; often **Port C → PEM → DO certificate API**. |

Without `APP_PLATFORM_ID` (or alias), DNS can still be automated; App Platform hostname registration must be done manually or via extended IaC.

### Cloudflare (Pages / Workers / zone custom hostnames)

| `resourceRefs` key | Accepted output keys | Purpose |
| ------------------ | -------------------- | ------- |
| `cloudflare_zone_id` | `CLOUDFLARE_ZONE_ID`, `cloudflare_zone_id` | Zone-scoped APIs (custom hostnames, records). |
| `cloudflare_account_id` | `CLOUDFLARE_ACCOUNT_ID`, `cloudflare_account_id` | Required with Pages project or Workers service for account-level APIs. |
| `cloudflare_pages_project` | `CLOUDFLARE_PAGES_PROJECT`, `cloudflare_pages_project`, `CF_PAGES_PROJECT` | Pages custom domains. |
| `cloudflare_workers_service` | `CLOUDFLARE_WORKERS_SERVICE`, `cloudflare_workers_service`, `WORKERS_SERVICE_NAME` | Workers custom domains. |

**Automation gate:** `shouldRunCloudflareEdgeAutomation` is true when a zone id is present, or when account id is present together with a Pages project or Workers service name.

## Requirements for automated custom domains (summary)

- **DO App Platform:** Export `APP_PLATFORM_ID` (or `digitalocean_app_id`) in preset outputs.
- **AWS CloudFront:** Export `CLOUDFRONT_DISTRIBUTION_ID` (or alias) and ensure `dns_name` + `canonical_hosted_zone_id` when apex alias routing on Route 53 is required.
- **DO load balancer + PartRocks LE:** Export load balancer id; user connects DO + DNS providers; Port C supplies PEM for upload.
- **Cloudflare edge:** Export zone id, and for Pages/Workers the account id plus project or service identifier as appropriate.

## AWS certificate / CloudFront (legacy note)

Templates that front the app with **CloudFront** should expose outputs that resolve to a **CloudFront DNS name** so the AWS provider can run ACM + alias attachment. Non-CloudFront targets skip that path by design (`certificateStatus: not_required` where applicable).
