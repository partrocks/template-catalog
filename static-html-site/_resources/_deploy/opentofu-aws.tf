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
  pr_release_archive_path = "{{ release.archivePath }}"

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
  bucket = local.website_bucket_name
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
    release_tag  = local.pr_release_tag
    archive_path = local.pr_release_archive_path
    bucket_name  = aws_s3_bucket.site.id
  }

  lifecycle {
    precondition {
      condition     = trimspace(local.pr_release_archive_path) != ""
      error_message = "release.archivePath was not provided. Ensure deploy preflight artifacts.type is archive."
    }
    precondition {
      condition     = fileexists("${local.pr_release_archive_path}/index.html")
      error_message = "index.html not found in staged release archive path."
    }
  }

  provisioner "local-exec" {
    command = "aws s3 sync \"${local.pr_release_archive_path}\" \"s3://${aws_s3_bucket.site.id}\" --delete --region \"${var.aws_region}\""
  }

  depends_on = [
    aws_s3_bucket_website_configuration.site,
    aws_s3_bucket_policy.site_public_read
  ]
}

output "SITE_URL" {
  description = "Public website URL."
  value       = "http://${aws_s3_bucket_website_configuration.site.website_endpoint}"
}

output "SITE_DNS_NAME" {
  description = "DNS name for the S3 website endpoint."
  value       = aws_s3_bucket_website_configuration.site.website_endpoint
}
