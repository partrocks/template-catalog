terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Application                  = local.app_scope
      ManagedBy                    = "partrocks"
      Environment                  = local.pr_environment_id
      Partrocks                    = "true"
      Provider                     = local.pr_provider_id
      "partrocks:app-id"           = local.pr_app_id_tag
      "partrocks:env-id"           = local.pr_environment_id
      "partrocks:project-scope-id" = local.pr_project_scope_id
      "partrocks:requirement-id"   = "deploy"
      "partrocks:resource-kind"    = "iac-template"
      "partrocks:template-id"      = local.pr_template_id
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  pr_environment_id      = "{{ environment.id }}"
  pr_safe_environment_id = "{{ environment.safeId }}"
  pr_provider_id         = "{{ provider.id }}"
  pr_app_id_tag          = "{{ application.safeId }}"
  pr_template_id         = "{{ template.id }}"
  pr_project_scope_id    = "{{ project.scopeId }}"
  pr_release_tag         = "{{ release.tag }}"
  pr_safe_release_tag    = "{{ release.safeTag }}"
  pr_archive_path_raw    = "{{ release.archivePath }}"
  pr_archive_path = (
    substr(trimspace(local.pr_archive_path_raw), 0, 2) == "{{" ? "" : trimspace(local.pr_archive_path_raw)
  )

  app_scope = substr(
    "${local.pr_safe_release_tag != "" ? local.pr_safe_release_tag : "site"}-${local.pr_safe_environment_id}",
    0,
    45
  )

  website_bucket_name_raw = substr(
    "partrocks-${local.pr_safe_release_tag != "" ? local.pr_safe_release_tag : "site"}-${local.pr_safe_environment_id}-${data.aws_caller_identity.current.account_id}-${var.aws_region}",
    0,
    63
  )

  website_bucket_name = trimsuffix(trimprefix(local.website_bucket_name_raw, "-"), "-")

  # When set (shareable gateway with gatewayFlavor cloudfront), IaC skips creating a second CloudFront;
  # PartRocks updates the bound distribution origin after apply using output S3_WEBSITE_ENDPOINT.
  pr_shareable_cloudfront_distribution_id   = trimspace("{{ constraints.partrocksShareableCloudFrontDistributionId }}")
  pr_shareable_cloudfront_distribution_domain = trimspace("{{ constraints.partrocksShareableCloudFrontDistributionDomain }}")
  use_partrocks_shareable_cloudfront_gateway = (
    local.pr_shareable_cloudfront_distribution_id != "" &&
    local.pr_shareable_cloudfront_distribution_domain != ""
  )
}

resource "aws_s3_bucket" "site" {
  bucket        = local.website_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "site_public_read" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = ["${aws_s3_bucket.site.arn}/*"]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.site]
}

resource "terraform_data" "sync_site_files" {
  triggers_replace = {
    release_tag     = local.pr_release_tag
    bucket_name     = aws_s3_bucket.site.id
    archive_path    = local.pr_archive_path
  }

  lifecycle {
    precondition {
      condition     = trimspace(local.pr_release_tag) != ""
      error_message = "release.tag is required to materialize static site files."
    }
    precondition {
      condition     = trimspace(local.pr_archive_path) != ""
      error_message = "release.archivePath is missing. Deploy must run archive preflight so the built static files are staged under /materialized; check preset preflights.artifacts."
    }
  }

  provisioner "local-exec" {
    command = <<-EOT
set -e
ARCH='${local.pr_archive_path}'
if [ -z "$ARCH" ] || [ ! -d "$ARCH" ]; then
  echo "partrocks: archive staging directory missing or not a directory: '$ARCH'" >&2
  exit 1
fi
SYNC_SRC="$ARCH"
if [ ! -f "$SYNC_SRC/index.html" ]; then
  echo "partrocks: expected index.html under staged archive path: $SYNC_SRC" >&2
  exit 1
fi
if grep -qE '/src/|src/main\\.tsx' "$SYNC_SRC/index.html"; then
  echo "partrocks: refusing to sync Vite dev index.html (references /src/). Use production dist/ from archive preflight build, not repo root." >&2
  exit 1
fi
aws s3 sync "$SYNC_SRC" "s3://${aws_s3_bucket.site.id}" --delete --region "${var.aws_region}"
EOT
  }

  depends_on = [
    aws_s3_bucket_website_configuration.site,
    aws_s3_bucket_policy.site_public_read
  ]
}

locals {
  cloudfront_route53_zone_id = "Z2FDTNDATAQYW2"
}

moved {
  from = aws_cloudfront_distribution.site
  to   = aws_cloudfront_distribution.site[0]
}

resource "aws_cloudfront_distribution" "site" {
  count = local.use_partrocks_shareable_cloudfront_gateway ? 0 : 1
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "partrocks-${local.app_scope}"
  price_class         = "PriceClass_100"

  origin {
    domain_name = aws_s3_bucket_website_configuration.site.website_endpoint
    origin_id    = "s3-website-${aws_s3_bucket.site.id}"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-website-${aws_s3_bucket.site.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  depends_on = [terraform_data.sync_site_files]
}

output "S3_WEBSITE_ENDPOINT" {
  description = "S3 website endpoint for shareable CloudFront origin sync (required when use_partrocks_shareable_cloudfront_gateway is true)."
  value       = aws_s3_bucket_website_configuration.site.website_endpoint
}

output "FRONT_DOOR_URL" {
  description = "HTTPS URL for the CloudFront distribution (use with shareable CloudFront gateway and custom domains)."
  value = (
    local.use_partrocks_shareable_cloudfront_gateway
    ? "https://${local.pr_shareable_cloudfront_distribution_domain}"
    : "https://${aws_cloudfront_distribution.site[0].domain_name}"
  )
}

output "FRONT_DOOR_DNS_NAME" {
  description = "CloudFront distribution domain for Route 53 alias or CNAME."
  value = (
    local.use_partrocks_shareable_cloudfront_gateway
    ? local.pr_shareable_cloudfront_distribution_domain
    : aws_cloudfront_distribution.site[0].domain_name
  )
}

output "FRONT_DOOR_HOSTED_ZONE_ID" {
  description = "Route 53 alias hosted zone id for CloudFront (fixed AWS value)."
  value       = local.cloudfront_route53_zone_id
}

output "CLOUDFRONT_DISTRIBUTION_ID" {
  description = "Distribution id for PartRocks domain binding / ACM attach (edge context)."
  value = (
    local.use_partrocks_shareable_cloudfront_gateway
    ? local.pr_shareable_cloudfront_distribution_id
    : aws_cloudfront_distribution.site[0].id
  )
}
