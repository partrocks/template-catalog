# Migrate static hosting: shareable ALB → CloudFront (CDN gateway)

PartRocks shareable **ALB** gateways use an **IP target group** in your default VPC. Your preset outputs must include `partrocks_alb_target_private_ips` (or set `partrocks_iac_owns_alb_targets=true` when ECS/ASG attaches the same target group). **Bare S3 static sites** do not expose private IPs there, so pairing **minimal S3** with an ALB gateway often yields an empty target group (503).

**Recommended path:** use a **CloudFront** shareable gateway with the **`aws/cloudfront-s3`** preset (see `static-react-vite` environment `cloud_https_cdn`).

## Steps

1. **App template**  
   Use a current static template that declares **`publicGatewayCdn`** with `constraints.sliceFlavor: cloudfront` in `resources.yaml` (see bundled `static-react-vite`).

2. **Environment / preset**  
   Point the app at environment **`cloud_https_cdn`** (preset **`aws/cloudfront-s3`**). For **ALB → EC2** (private IP target), use **`cloud_https_alb`** with **`aws/alb-ec2`** and bind **`publicGatewayAlb`** (`sliceFlavor: alb`). Do not pair a bare S3-only preset with an ALB gateway unless you add real IP targets.

3. **Shared gateway**  
   - Destroy or stop using the old **ALB** shareable gateway binding for that environment, or create a **new** shareable gateway from deploy: with CloudFront flavor, PartRocks provisions a distribution and records `cloudfrontDistributionId` for teardown.  
   - Bind the environment to the **CloudFront** gateway (`publicGatewayCdn`).

4. **Apply**  
   Run deploy/apply so PartRocks provisions the app CloudFront distribution and surfaces outputs such as `DNS_NAME` / `HOSTED_ZONE_ID` (for Route 53 alias) and app URL.

5. **DNS / domain link**  
   Point your hostname at the **distribution** (CNAME to the distribution domain or Route 53 alias to CloudFront). Use the platform domain-linking flow so TLS and records match the **CloudFront** edge (including ACM in `us-east-1` for CloudFront when applicable).

6. **Teardown**  
   Removing the shareable resource from PartRocks triggers destroy: CloudFront distributions are disabled and deleted; ALB paths remove listener, load balancer, and target groups—as with ALB, this is irreversible for that provisioned resource.

## Rollback

If you must stay on ALB, add **in-VPC targets** (e.g. ECS service attached to the PartRocks target group, or outputs for `partrocks_alb_target_private_ips`). That is an advanced pattern; prefer CloudFront + `cloud_https_cdn` for static sites.
