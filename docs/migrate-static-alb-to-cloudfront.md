# Migrate static hosting: shareable ALB → CloudFront (Secure Edge)

PartRocks shareable **ALB** gateways use an **IP target group** in your default VPC. OpenTofu must output `partrocks_alb_target_private_ips` (or set `partrocks_iac_owns_alb_targets=true` when ECS/ASG attaches the same target group). **Bare S3 static sites** do not expose private IPs there, so pairing **minimal S3** with an ALB gateway often yields an empty target group (503).

**Recommended path:** use a **CloudFront** shareable gateway with the **Secure Edge** preset (CloudFront + S3 in your stack).

## Steps

1. **App template**  
   Use a current static template that sets `publicGateway.constraints.gatewayFlavor: cloudfront` in `resources.yaml` (already true for bundled static apps).

2. **Preset**  
   Switch the environment to **`aws/secure-edge`** (and order it before `aws/minimal-http` in `environments.yaml` if you maintain a fork).

3. **Shared gateway**  
   - Destroy or stop using the old **ALB** shareable gateway binding for that environment, or create a **new** shareable gateway from deploy: with CloudFront flavor, PartRocks provisions a distribution and records `cloudfrontDistributionId` for teardown.  
   - Bind the environment to the **CloudFront** gateway.

4. **Apply**  
   Run deploy/apply so OpenTofu creates the app CloudFront distribution and outputs such as `DNS_NAME` / `HOSTED_ZONE_ID` (for Route 53 alias) and app URL.

5. **DNS / domain link**  
   Point your hostname at the **distribution** (CNAME to the distribution domain or Route 53 alias to CloudFront). Use the platform domain-linking flow so TLS and records match the **CloudFront** edge (including ACM in `us-east-1` for CloudFront when applicable).

6. **Teardown**  
   Removing the shareable resource from PartRocks triggers destroy: CloudFront distributions are disabled and deleted; ALB paths remove listener, load balancer, and target groups—as with ALB, this is irreversible for that provisioned resource.

## Rollback

If you must stay on ALB, add **in-VPC targets** (e.g. ECS service attached to the PartRocks target group, or outputs for `partrocks_alb_target_private_ips`). That is an advanced pattern; prefer CloudFront + Secure Edge for static sites.
