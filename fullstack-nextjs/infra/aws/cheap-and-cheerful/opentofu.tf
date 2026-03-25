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
      Application = local.app_scope
      ManagedBy   = "partrocks"
      Environment = local.pr_environment_id
      Provider    = local.pr_provider_id
      Partrocks   = "true"
    }
  }
}

locals {
  pr_environment_id         = "{{ environment.id }}"
  pr_safe_environment_id    = "{{ environment.safeId }}"
  pr_provider_id            = "{{ provider.id }}"
  pr_release_ref            = "{{ release.imageRef }}"
  pr_safe_release_repo_name = "{{ release.safeImageName }}"
  pr_app_port               = "{{ constraints.appPort }}"
  pr_app_health_path        = "{{ constraints.appHealthPath }}"
  pr_apprunner_cpu          = "{{ constraints.appRunnerCpu }}"
  pr_apprunner_memory       = "{{ constraints.appRunnerMemory }}"
  pr_apprunner_min_size     = "{{ constraints.appRunnerMinSize }}"
  pr_apprunner_max_size     = "{{ constraints.appRunnerMaxSize }}"
  pr_start_command          = "{{ constraints.appRunnerStartCommand }}"

  # Shared resources now provide database and secret values.
  pr_database_url   = "{{ constraints.databaseUrl }}"
  pr_app_secret     = "{{ constraints.appSecret }}"
  pr_jwt_secret_key = "{{ constraints.jwtSecretKey }}"

  scope_seed = "${local.pr_safe_release_repo_name}-${local.pr_safe_environment_id}"
  app_scope_hash = substr(
    sha1(local.scope_seed),
    0,
    8
  )
  app_scope = substr(
    "${local.pr_safe_release_repo_name}-${local.pr_safe_environment_id}-${local.app_scope_hash}",
    0,
    45
  )
  app_scope_short  = substr(local.app_scope, 0, 25)
  app_service_name = substr("partrocks-${local.app_scope}", 0, 40)
}

resource "aws_iam_role" "apprunner_access" {
  name = "${local.app_scope}-apprunner-access"
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
        port          = local.pr_app_port
        start_command = local.pr_start_command

        runtime_environment_variables = merge(
          {
            APP_ENV         = "prod"
            APP_DEBUG       = "0"
            APP_RUN_COMMAND = "php -S 0.0.0.0:${local.pr_app_port} -t public"
          },
          trimspace(local.pr_database_url) != "" ? { DATABASE_URL = local.pr_database_url } : {},
          trimspace(local.pr_app_secret) != "" ? { APP_SECRET = local.pr_app_secret } : {},
          trimspace(local.pr_jwt_secret_key) != "" ? { JWT_SECRET_KEY = local.pr_jwt_secret_key } : {}
        )
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

  depends_on = [aws_iam_role_policy_attachment.apprunner_access_ecr]
}

locals {
  app_dns_name = split("/", trimprefix(aws_apprunner_service.app.service_url, "https://"))[0]
}

output "APP_BASE_URL" {
  description = "Application base URL."
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "DATABASE_URL" {
  description = "Resolved DATABASE_URL injected via shared resource binding."
  value       = local.pr_database_url
  sensitive   = true
}

output "APP_SECRET" {
  description = "Resolved APP_SECRET injected via environment/binding secrets."
  value       = local.pr_app_secret
  sensitive   = true
}

output "JWT_SECRET_KEY" {
  description = "Resolved JWT secret key injected via environment/binding secrets."
  value       = local.pr_jwt_secret_key
  sensitive   = true
}

output "APP_ENV" {
  value = "prod"
}

output "FRONT_DOOR_URL" {
  description = "Public app URL; gateway routing is managed outside template IaC."
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "FRONT_DOOR_DNS_NAME" {
  description = "DNS name for direct app ingress when shared gateway is external."
  value       = local.app_dns_name
}

output "FRONT_DOOR_HOSTED_ZONE_ID" {
  description = "Hosted zone id is managed by shared ingress binding."
  value       = ""
}
