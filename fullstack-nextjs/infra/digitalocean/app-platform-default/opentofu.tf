terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  pr_environment_id      = "{{ environment.id }}"
  pr_safe_environment_id = "{{ environment.safeId }}"
  pr_provider_id         = "{{ provider.id }}"
  pr_release_tag         = "{{ release.tag }}"
  pr_release_ref         = "{{ release.imageRef }}"
  pr_safe_release_repo_name = "{{ release.safeImageName }}"
  pr_app_port            = "{{ constraints.appPort }}"
  pr_app_health_path     = "{{ constraints.appHealthPath }}"
  pr_do_region           = "{{ constraints.doRegion }}"
  pr_do_instance_size    = "{{ constraints.doInstanceSize }}"
  pr_do_instance_count   = "{{ constraints.doInstanceCount }}"
  app_scope_hash = substr(
    sha1(trimspace(local.pr_release_ref) != "" ? local.pr_release_ref : local.pr_safe_environment_id),
    0,
    8
  )
  app_scope        = substr("${local.pr_safe_release_repo_name}-${local.pr_safe_environment_id}-${local.app_scope_hash}", 0, 45)
  app_scope_short  = substr(local.app_scope, 0, 25)
  app_service_name = substr("partrocks-${local.app_scope}", 0, 40)
  database_name = "appdb"

  # Preset must define constraints.doRegion; if interpolation failed, placeholder still contains "{{".
  pr_do_region_resolved = (
    length(regexall("\\{\\{", local.pr_do_region)) > 0 || trimspace(local.pr_do_region) == "" ?
    "nyc1" : trimspace(local.pr_do_region)
  )
  pr_do_instance_size_resolved = (
    length(regexall("\\{\\{", local.pr_do_instance_size)) > 0 || trimspace(local.pr_do_instance_size) == "" ?
    "basic-xxs" : trimspace(local.pr_do_instance_size)
  )

  do_region_db = local.pr_do_region_resolved
  # App Platform uses the region slug without the trailing digit (e.g. lon from lon1). Uppercase
  # slugs (e.g. LON1 from UI) must be normalized — the previous [a-z]+ pattern failed on those.
  do_region_app = lower(regex("^([a-zA-Z]+)[0-9]*$", local.do_region_db))

  image_ref_parts   = split(":", local.pr_release_ref)
  image_tag         = length(local.image_ref_parts) > 1 ? local.image_ref_parts[length(local.image_ref_parts) - 1] : "latest"
  image_without_tag = length(local.image_ref_parts) > 1 ? join(":", slice(local.image_ref_parts, 0, length(local.image_ref_parts) - 1)) : local.pr_release_ref
  image_path_parts  = split("/", local.image_without_tag)
  release_ref_tail  = length(local.image_path_parts) > 0 ? local.image_path_parts[length(local.image_path_parts) - 1] : "app"
  registry_type = (
    can(regex("registry\\.digitalocean\\.com", local.pr_release_ref)) ? "DOCR" :
    can(regex("ghcr\\.io", local.pr_release_ref)) ? "GHCR" :
    "DOCKER_HUB"
  )
  do_registry = (
    local.registry_type == "DOCR" ? (length(local.image_path_parts) >= 2 ? local.image_path_parts[1] : "") :
    local.registry_type == "GHCR" ? (length(local.image_path_parts) >= 2 ? local.image_path_parts[1] : "") :
    length(local.image_path_parts) >= 2 ? (local.image_path_parts[0] == "docker.io" ? local.image_path_parts[1] : local.image_path_parts[0]) : ""
  )
  do_repository = (
    local.registry_type == "DOCR" ? (length(local.image_path_parts) >= 3 ? join("/", slice(local.image_path_parts, 2, length(local.image_path_parts))) : local.release_ref_tail) :
    local.registry_type == "GHCR" ? (length(local.image_path_parts) >= 3 ? join("/", slice(local.image_path_parts, 2, length(local.image_path_parts))) : local.release_ref_tail) :
    length(local.image_path_parts) >= 2 ? (local.image_path_parts[0] == "docker.io" ? join("/", slice(local.image_path_parts, 2, length(local.image_path_parts))) : (length(local.image_path_parts) >= 3 ? join("/", slice(local.image_path_parts, 1, length(local.image_path_parts))) : local.image_path_parts[1])) : local.release_ref_tail
  )
}

resource "digitalocean_database_cluster" "postgres" {
  name       = "partrocks-${local.app_scope}-postgres"
  engine     = "pg"
  version    = "16"
  size       = "db-s-1vcpu-1gb"
  region     = local.do_region_db
  node_count = 1
}

resource "digitalocean_database_db" "appdb" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = local.database_name
}

resource "random_password" "app_secret" {
  length  = 64
  special = false
}

resource "random_password" "jwt_secret_key" {
  length  = 96
  special = false
}

locals {
  database_url = "postgresql://${digitalocean_database_cluster.postgres.user}:${urlencode(digitalocean_database_cluster.postgres.password)}@${digitalocean_database_cluster.postgres.host}:${digitalocean_database_cluster.postgres.port}/${local.database_name}?sslmode=require&serverVersion=16&charset=utf8"
  app_dns_name = split("/", trimprefix(digitalocean_app.app.live_url, "https://"))[0]
}

resource "digitalocean_app" "app" {
  spec {
    name   = local.app_service_name
    region = local.do_region_app

    service {
      name               = "web"
      instance_count     = try(tonumber(local.pr_do_instance_count), 1)
      instance_size_slug = local.pr_do_instance_size_resolved
      http_port          = tonumber(local.pr_app_port)

      image {
        registry_type = local.registry_type
        registry      = local.do_registry
        repository    = local.do_repository
        tag           = local.image_tag
      }

      health_check {
        http_path             = local.pr_app_health_path
        initial_delay_seconds = 30
        period_seconds        = 10
        timeout_seconds       = 3
        success_threshold     = 1
        failure_threshold     = 3
      }

      env {
        key   = "APP_ENV"
        value = "prod"
        type  = "GENERAL"
      }

      env {
        key   = "DATABASE_URL"
        value = local.database_url
        type  = "SECRET"
      }

      env {
        key   = "APP_SECRET"
        value = random_password.app_secret.result
        type  = "SECRET"
      }

      env {
        key   = "JWT_SECRET_KEY"
        value = random_password.jwt_secret_key.result
        type  = "SECRET"
      }
    }
  }
}

resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "app"
    value = digitalocean_app.app.id
  }
}

output "APP_BASE_URL" {
  description = "Application base URL."
  value       = digitalocean_app.app.live_url
}

output "APP_DNS_NAME" {
  description = "DNS hostname for the application URL."
  value       = local.app_dns_name
}

output "DATABASE_URL" {
  description = "Database connection string (sensitive)."
  value       = local.database_url
  sensitive   = true
}

output "APP_SECRET" {
  description = "APP_SECRET value (sensitive)."
  value       = random_password.app_secret.result
  sensitive   = true
}

output "JWT_SECRET_KEY" {
  description = "JWT secret key (sensitive)."
  value       = random_password.jwt_secret_key.result
  sensitive   = true
}

output "APP_ENV" {
  value = "prod"
}
