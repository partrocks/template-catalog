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
      ManagedBy   = "partrocks"
      Environment = local.pr_environment_id
      Provider    = local.pr_provider_id
      Partrocks   = "true"
      Application = local.app_scope
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  pr_environment_id      = "{{ environment.id }}"
  pr_safe_environment_id = "{{ environment.safeId }}"
  pr_provider_id         = "{{ provider.id }}"
  pr_release_tag         = "{{ release.tag }}"
  pr_safe_release_tag    = "{{ release.safeTag }}"

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
    release_tag = local.pr_release_tag
    bucket_name = aws_s3_bucket.site.id
  }

  lifecycle {
    precondition {
      condition     = trimspace(local.pr_release_tag) != ""
      error_message = "release.tag is required to materialize static site files."
    }
  }

  provisioner "local-exec" {
    command = "tmp_dir=$(mktemp -d) && git -C /app archive --format=tar \"${local.pr_release_tag}\" | tar -xf - -C \"$tmp_dir\" && test -f \"$tmp_dir/index.html\" && aws s3 sync \"$tmp_dir\" \"s3://${aws_s3_bucket.site.id}\" --delete --region \"${var.aws_region}\" && rm -rf \"$tmp_dir\""
  }

  depends_on = [
    aws_s3_bucket_website_configuration.site,
    aws_s3_bucket_policy.site_public_read
  ]
}

resource "aws_cloudfront_distribution" "site_frontdoor" {
  enabled = true
  aliases = []
  origin {
    domain_name = aws_s3_bucket_website_configuration.site.website_endpoint
    origin_id   = "s3-website-origin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "s3-website-origin"
    viewer_protocol_policy = "redirect-to-https"
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
  default_root_object = "index.html"
}

output "FRONT_DOOR_URL" {
  description = "CloudFront URL for the static site."
  value       = "https://${aws_cloudfront_distribution.site_frontdoor.domain_name}"
}

output "FRONT_DOOR_DNS_NAME" {
  description = "DNS name for the CloudFront distribution."
  value       = aws_cloudfront_distribution.site_frontdoor.domain_name
}

output "FRONT_DOOR_HOSTED_ZONE_ID" {
  description = "Route53 hosted zone id for CloudFront alias records."
  value       = aws_cloudfront_distribution.site_frontdoor.hosted_zone_id
}
