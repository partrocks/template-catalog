terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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
  pr_environment_id       = "{{ environment.id }}"
  pr_provider_id          = "{{ provider.id }}"
  pr_release_tag          = "{{ release.tag }}"
  pr_release_ref          = "{{ release.imageRef }}"
  pr_app_port             = "{{ constraints.appPort }}"
  pr_app_health_path      = "{{ constraints.appHealthPath }}"
  pr_apprunner_cpu        = "{{ constraints.appRunnerCpu }}"
  pr_apprunner_memory     = "{{ constraints.appRunnerMemory }}"
  pr_apprunner_min_size   = "{{ constraints.appRunnerMinSize }}"
  pr_apprunner_max_size   = "{{ constraints.appRunnerMaxSize }}"
  pr_start_command        = "{{ constraints.appRunnerStartCommand }}"

  safe_environment_id = replace(
    replace(
      replace(replace(replace(lower(local.pr_environment_id), "{", ""), "}", ""), " ", ""),
      ".",
      "-"
    ),
    "_",
    "-"
  )

  # Scope resource names to app+env to avoid cross-project collisions.
  release_ref_tail = trimspace(local.pr_release_ref) != "" ? element(
    split("/", local.pr_release_ref),
    length(split("/", local.pr_release_ref)) - 1
  ) : "app"

  release_repo_name = split("@", local.release_ref_tail)[0]

  safe_release_repo_name = replace(
    replace(
      replace(replace(replace(lower(local.release_repo_name), "{", ""), "}", ""), " ", ""),
      ".",
      "-"
    ),
    "_",
    "-"
  )

  app_scope_hash = substr(
    sha1(trimspace(local.pr_release_ref) != "" ? local.pr_release_ref : local.safe_environment_id),
    0,
    8
  )

  app_scope         = substr("${local.safe_release_repo_name}-${local.safe_environment_id}-${local.app_scope_hash}", 0, 45)
  app_scope_short   = substr(local.app_scope, 0, 25)
  app_service_name  = substr("partrocks-${local.app_scope}", 0, 40)
  database_name     = "appdb"
  database_username = "appuser"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "postgres" {
  name_prefix = "partrocks-${local.app_scope}-postgres-"
  description = "Postgres access within default VPC CIDR"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.apprunner_vpc_connector.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "apprunner_vpc_connector" {
  name_prefix = "partrocks-${local.app_scope}-apprunner-vpc-"
  description = "App Runner VPC connector egress"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "partrocks-${local.app_scope}-postgres-subnets"
  subnet_ids = data.aws_subnets.default_vpc_subnets.ids
}

resource "random_password" "database_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}:?"
}

resource "aws_db_instance" "postgres" {
  identifier                 = "partrocks-${local.app_scope}-postgres"
  allocated_storage          = 20
  max_allocated_storage      = 100
  storage_type               = "gp3"
  engine                     = "postgres"
  instance_class             = "db.t3.micro"
  db_name                    = local.database_name
  username                   = local.database_username
  password                   = random_password.database_password.result
  db_subnet_group_name       = aws_db_subnet_group.postgres.name
  vpc_security_group_ids     = [aws_security_group.postgres.id]
  backup_retention_period    = 7
  storage_encrypted          = true
  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true
  apply_immediately          = true
}

locals {
  database_url = "postgresql://${local.database_username}:${random_password.database_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${local.database_name}?serverVersion=16&charset=utf8"
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "partrocks/${local.app_scope}/DATABASE_URL"
  description             = "Symfony DATABASE_URL for ${local.pr_environment_id}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = local.database_url
}

resource "random_password" "app_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "app_secret" {
  name                    = "partrocks/${local.app_scope}/APP_SECRET"
  description             = "Symfony APP_SECRET for ${local.pr_environment_id}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_secret" {
  secret_id     = aws_secretsmanager_secret.app_secret.id
  secret_string = random_password.app_secret.result
}

resource "random_password" "jwt_secret_key" {
  length  = 96
  special = false
}

resource "aws_secretsmanager_secret" "jwt_secret_key" {
  name                    = "partrocks/${local.app_scope}/JWT_SECRET_KEY"
  description             = "Symfony JWT secret key for ${local.pr_environment_id}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt_secret_key" {
  secret_id     = aws_secretsmanager_secret.jwt_secret_key.id
  secret_string = random_password.jwt_secret_key.result
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

resource "aws_iam_role" "apprunner_instance" {
  name = "${local.app_scope}-apprunner-instance"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "apprunner_secrets" {
  name = "${local.app_scope}-apprunner-secrets"
  role = aws_iam_role.apprunner_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.database_url.arn,
          aws_secretsmanager_secret.app_secret.arn,
          aws_secretsmanager_secret.jwt_secret_key.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_apprunner_vpc_connector" "app" {
  vpc_connector_name = "${local.app_scope_short}-apprunner-vpc"
  subnets            = data.aws_subnets.default_vpc_subnets.ids
  security_groups    = [aws_security_group.apprunner_vpc_connector.id]
}

resource "aws_apprunner_auto_scaling_configuration_version" "app" {
  auto_scaling_configuration_name = "${local.app_scope_short}-autoscaling"
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

        runtime_environment_variables = {
          APP_ENV = "prod"
          APP_RUN_COMMAND = "php-fpm -F"
        }

        runtime_environment_secrets = {
          DATABASE_URL   = aws_secretsmanager_secret.database_url.arn
          APP_SECRET     = aws_secretsmanager_secret.app_secret.arn
          JWT_SECRET_KEY = aws_secretsmanager_secret.jwt_secret_key.arn
        }
      }
    }
  }

  instance_configuration {
    cpu               = local.pr_apprunner_cpu
    memory            = local.pr_apprunner_memory
    instance_role_arn = aws_iam_role.apprunner_instance.arn
  }

  network_configuration {
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.app.arn
    }
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = local.pr_app_health_path
  }

  depends_on = [
    aws_iam_role_policy_attachment.apprunner_access_ecr,
    aws_iam_role_policy.apprunner_secrets
  ]
}

output "APP_BASE_URL" {
  description = "Application base URL."
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "DATABASE_URL" {
  description = "Secrets Manager reference for DATABASE_URL."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "APP_SECRET" {
  description = "Secrets Manager reference for APP_SECRET."
  value       = aws_secretsmanager_secret.app_secret.arn
}

output "JWT_SECRET_KEY" {
  description = "Secrets Manager reference for JWT secret key."
  value       = aws_secretsmanager_secret.jwt_secret_key.arn
}

output "APP_ENV" {
  value = "prod"
}