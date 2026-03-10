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
  pr_environment_id     = "{{ environment.id }}"
  pr_provider_id        = "{{ provider.id }}"
  pr_release_ref        = "{{ release.imageRef }}"
  pr_app_port           = "{{ constraints.appPort }}"
  pr_app_health_path    = "{{ constraints.appHealthPath }}"
  pr_apprunner_cpu      = "{{ constraints.appRunnerCpu }}"
  pr_apprunner_memory   = "{{ constraints.appRunnerMemory }}"
  pr_apprunner_min_size = "{{ constraints.appRunnerMinSize }}"
  pr_apprunner_max_size = "{{ constraints.appRunnerMaxSize }}"

  safe_environment_id = trimsuffix(
    trimprefix(
      replace(
        replace(
          replace(
            replace(
              replace(lower(local.pr_environment_id), " ", "-"),
              ".",
              "-"
            ),
            "_",
            "-"
          ),
          ":",
          "-"
        ),
        "/",
        "-"
      ),
      "-"
    ),
    "-"
  )

  release_ref_tail   = trimspace(local.pr_release_ref) != "" ? element(split("/", local.pr_release_ref), length(split("/", local.pr_release_ref)) - 1) : "app"
  release_repo_name  = split(":", split("@", local.release_ref_tail)[0])[0]
  safe_release_name  = trimsuffix(trimprefix(replace(replace(replace(replace(replace(lower(local.release_repo_name), " ", "-"), ".", "-"), "_", "-"), ":", "-"), "/", "-"), "-"), "-")
  scope_seed         = "${local.safe_release_name}-${local.safe_environment_id}"
  app_scope_hash     = substr(sha1(local.scope_seed), 0, 8)
  app_scope          = substr("${local.safe_release_name}-${local.safe_environment_id}-${local.app_scope_hash}", 0, 45)
  app_scope_short    = substr(local.app_scope, 0, 25)
  app_service_name   = substr("partrocks-${local.app_scope}", 0, 40)
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

output "APP_BASE_URL" {
  description = "Application base URL."
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "APP_ENV" {
  value = "prod"
}
