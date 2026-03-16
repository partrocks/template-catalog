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

locals {
  pr_environment_id       = "{{ environment.id }}"
  pr_safe_environment_id  = "{{ environment.safeId }}"
  pr_provider_id          = "{{ provider.id }}"
  pr_release_ref          = "{{ release.imageRef }}"
  pr_safe_release_name    = "{{ release.safeImageName }}"
  pr_app_port             = "{{ constraints.appPort }}"
  pr_app_health_path      = "{{ constraints.appHealthPath }}"
  pr_apprunner_cpu        = "{{ constraints.appRunnerCpu }}"
  pr_apprunner_memory     = "{{ constraints.appRunnerMemory }}"
  pr_apprunner_min_size   = "{{ constraints.appRunnerMinSize }}"
  pr_apprunner_max_size   = "{{ constraints.appRunnerMaxSize }}"

  scope_seed         = "${local.pr_safe_release_name}-${local.pr_safe_environment_id}"
  app_scope_hash     = substr(sha1(local.scope_seed), 0, 8)
  app_scope          = substr("${local.pr_safe_release_name}-${local.pr_safe_environment_id}-${local.app_scope_hash}", 0, 45)
  app_scope_short    = substr(local.app_scope, 0, 25)
  app_service_name   = substr("partrocks-${local.app_scope}", 0, 40)
  app_shared_seed    = local.pr_safe_release_name
  app_shared_hash    = substr(sha1(local.app_shared_seed), 0, 8)
  app_shared_scope   = substr("${local.pr_safe_release_name}-${local.app_shared_hash}", 0, 45)
}

resource "aws_iam_role" "apprunner_access" {
  name = "${local.app_scope_short}-apprunner-access"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apprunner_access_ecr" {
  role       = aws_iam_role.apprunner_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

resource "aws_apprunner_auto_scaling_configuration_version" "app" {
  auto_scaling_configuration_name = substr("${local.app_scope_short}-asg", 0, 32)
  min_size                        = tonumber(local.pr_apprunner_min_size)
  max_size                        = tonumber(local.pr_apprunner_max_size)
}

resource "aws_apprunner_service" "app" {
  service_name                   = local.app_service_name
  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.app.arn

  source_configuration {
    auto_deployments_enabled = false

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access.arn
    }

    image_repository {
      image_repository_type = "ECR"
      image_identifier      = local.pr_release_ref

      image_configuration {
        port = local.pr_app_port
        runtime_environment_variables = {
          APP_ENV = "prod"
        }
      }
    }
  }

  instance_configuration {
    cpu    = local.pr_apprunner_cpu
    memory = local.pr_apprunner_memory
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = local.pr_app_health_path
  }

  depends_on = [
    aws_iam_role_policy_attachment.apprunner_access_ecr
  ]
}

resource "aws_cloudfront_distribution" "app_frontdoor" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "PartRocks App Runner front door"
  default_root_object = ""
  price_class         = "PriceClass_100"
  tags = {
    PartrocksSharedFrontDoorKey = local.app_shared_scope
  }

  origin {
    domain_name = aws_apprunner_service.app.service_url
    origin_id   = "apprunner-${local.app_scope_hash}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "apprunner-${local.app_scope_hash}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    forwarded_values {
      query_string = true
      # Do not forward viewer Host header to App Runner.
      # Forwarding Host causes App Runner/envoy to return 404 for custom domains.
      headers      = []
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "APP_BASE_URL" {
  description = "Application base URL."
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "APP_ENV" {
  value = "prod"
}

output "FRONT_DOOR_URL" {
  description = "CloudFront URL intended for domain routing."
  value       = "https://${aws_cloudfront_distribution.app_frontdoor.domain_name}"
}

output "FRONT_DOOR_DNS_NAME" {
  description = "Alias-compatible DNS target for Route53."
  value       = aws_cloudfront_distribution.app_frontdoor.domain_name
}

output "FRONT_DOOR_HOSTED_ZONE_ID" {
  description = "Route53 hosted zone id for the CloudFront target."
  value       = aws_cloudfront_distribution.app_frontdoor.hosted_zone_id
}

output "APP_SHARED_FRONT_DOOR_KEY" {
  description = "App-scoped shared front-door identity key."
  value       = local.app_shared_scope
}

output "APP_SHARED_FRONT_DOOR_DNS_NAME" {
  description = "App-scoped shared front-door DNS target."
  value       = aws_cloudfront_distribution.app_frontdoor.domain_name
}

output "APP_SHARED_FRONT_DOOR_HOSTED_ZONE_ID" {
  description = "App-scoped shared front-door hosted zone id."
  value       = aws_cloudfront_distribution.app_frontdoor.hosted_zone_id
}
