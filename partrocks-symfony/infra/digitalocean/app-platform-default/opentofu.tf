terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

locals {
  pr_environment_id         = "{{ environment.id }}"
  pr_safe_environment_id    = "{{ environment.safeId }}"
  pr_provider_id            = "{{ provider.id }}"
  pr_release_tag            = "{{ release.tag }}"
  pr_release_ref            = "{{ release.imageRef }}"
  pr_safe_release_repo_name = "{{ release.safeImageName }}"
  pr_app_port               = "{{ constraints.appPort }}"
  pr_app_health_path        = "{{ constraints.appHealthPath }}"
  pr_do_region              = "{{ constraints.doRegion }}"
  pr_do_instance_size       = "{{ constraints.doInstanceSize }}"
  pr_do_instance_count      = "{{ constraints.doInstanceCount }}"
  pr_database_url           = "{{ constraints.databaseUrl }}"
  pr_app_secret             = "{{ constraints.appSecret }}"
  pr_jwt_secret_key         = "{{ constraints.jwtSecretKey }}"
  app_scope_hash = substr(
    sha1(trimspace(local.pr_release_ref) != "" ? local.pr_release_ref : local.pr_safe_environment_id),
    0,
    8
  )
  app_scope = substr("${local.pr_safe_release_repo_name}-${local.pr_safe_environment_id}-${local.app_scope_hash}", 0, 45)
  # DO spec.name: pr-{scope}, scope = hash-app-env (hash first so 32-char cap trims app/env tail, not uniqueness).
  do_app_name_scope = "${local.app_scope_hash}-${local.pr_safe_release_repo_name}-${local.pr_safe_environment_id}"
  # Name must match ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ — max 32 chars and cannot end with '-'.
  # substr(0,32) commonly ends on '-' (e.g. before env segment). Strip trailing '-' without
  # regexreplace (some deploy runners ship an older OpenTofu that lacks that builtin).
  app_service_name_trunc = substr(lower("pr-${local.do_app_name_scope}"), 0, 32)
  app_service_name_len   = length(local.app_service_name_trunc)
  app_service_name_last = (
    local.app_service_name_len > 0 ?
    substr(local.app_service_name_trunc, local.app_service_name_len - 1, 1) : ""
  )
  app_service_name_core = (
    local.app_service_name_last == "-" && local.app_service_name_len > 1 ?
    substr(local.app_service_name_trunc, 0, local.app_service_name_len - 1) :
    local.app_service_name_trunc
  )
  app_service_name = (
    local.app_service_name_core != "" ? local.app_service_name_core : "pr-${local.app_scope_hash}"
  )

  # Preset must define constraints.doRegion; if interpolation failed, placeholder still contains "{{".
  # Lowercase DO slugs here so DB + app always match (UI may send LON1).
  pr_do_region_resolved = (
    length(regexall("\\{\\{", local.pr_do_region)) > 0 || trimspace(local.pr_do_region) == "" ?
    "nyc1" : lower(trimspace(local.pr_do_region))
  )
  pr_do_instance_size_resolved = (
    length(regexall("\\{\\{", local.pr_do_instance_size)) > 0 || trimspace(local.pr_do_instance_size) == "" ?
    "basic-xxs" : trimspace(local.pr_do_instance_size)
  )

  do_region_db = local.pr_do_region_resolved
  # App Platform wants the region slug without the trailing digit (lon from lon1). Pattern has no
  # capture groups, so regex() returns a STRING (not a list) — works on all Terraform/OpenTofu versions.
  do_region_app = regex("^[a-z]+", local.do_region_db)

  image_ref_parts   = split(":", local.pr_release_ref)
  image_tag         = length(local.image_ref_parts) > 1 ? local.image_ref_parts[length(local.image_ref_parts) - 1] : "latest"
  image_without_tag = length(local.image_ref_parts) > 1 ? join(":", slice(local.image_ref_parts, 0, length(local.image_ref_parts) - 1)) : local.pr_release_ref
  registry_type = (
    can(regex("registry\\.digitalocean\\.com", local.pr_release_ref)) ? "DOCR" :
    can(regex("ghcr\\.io", local.pr_release_ref)) ? "GHCR" :
    "DOCKER_HUB"
  )

  # App spec requires non-empty repository. Path after registry host; docker.io/nginx:tag must not
  # use slice(2,...) on a two-segment path (that produced an empty repository).
  do_image_stripped = (
    trimspace(local.image_without_tag) == "" ? "" :
    local.registry_type == "DOCR" ? trimprefix(local.image_without_tag, "registry.digitalocean.com/") :
    local.registry_type == "GHCR" ? trimprefix(local.image_without_tag, "ghcr.io/") :
    trimprefix(trimprefix(local.image_without_tag, "docker.io/"), "registry-1.docker.io/")
  )
  do_repo_segments = local.do_image_stripped != "" ? split("/", local.do_image_stripped) : []
  do_registry = (
    local.registry_type == "DOCR" ? (length(local.do_repo_segments) >= 1 ? local.do_repo_segments[0] : "") :
    local.registry_type == "GHCR" ? (length(local.do_repo_segments) >= 1 ? local.do_repo_segments[0] : "") :
    ""
  )
  do_repository = (
    local.registry_type == "DOCR" ? (
      length(local.do_repo_segments) >= 2 ? join("/", slice(local.do_repo_segments, 1, length(local.do_repo_segments))) : ""
    ) :
    local.registry_type == "GHCR" ? (
      length(local.do_repo_segments) >= 2 ? join("/", slice(local.do_repo_segments, 1, length(local.do_repo_segments))) : ""
    ) :
    length(local.do_repo_segments) == 0 ? "" : (
      length(local.do_repo_segments) == 1 && local.do_repo_segments[0] != "" ? "library/${local.do_repo_segments[0]}" : join("/", local.do_repo_segments)
    )
  )
}

locals {
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
        value = local.pr_database_url
        type  = "SECRET"
      }

      env {
        key   = "APP_SECRET"
        value = local.pr_app_secret
        type  = "SECRET"
      }

      env {
        key   = "JWT_SECRET_KEY"
        value = local.pr_jwt_secret_key
        type  = "SECRET"
      }
    }
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
