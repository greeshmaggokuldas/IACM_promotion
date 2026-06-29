terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.31"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

locals {
  spec       = var.template_spec != null ? var.template_spec : {}
  # Handle both flat structure and nested 'template:' wrapper
  inner      = try(local.spec.template, local.spec)
  name       = try(local.inner.name, "promoted-template")
  identifier = try(local.inner.identifier, replace(local.name, " ", "_"))
  version    = try(local.inner.versionLabel, "1.0.0")
  use_git_backend = var.git_connector_ref != ""
}

# =============================================================================
# Import template from Git (git-backed) using Harness API
# This registers the template in Harness pointing to the existing YAML file
# in the Git repo — it does NOT create a new file.
# =============================================================================

resource "terraform_data" "import_template" {
  count = var.is_project_scope && local.use_git_backend ? 1 : 0

  input = {
    identifier  = local.identifier
    name        = local.name
    version     = local.version
    org_id      = var.org_id
    project_id  = var.project_id
    connector   = var.git_connector_ref
    repo        = var.github_repo
    branch      = var.github_branch
    file_path   = var.template_yaml_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -s -X POST \
        "${var.harness_endpoint}/template/api/templates/import/${local.identifier}?accountIdentifier=${var.account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" \
        -d '{
          "template_import_request": {
            "template_name": "${local.name}",
            "template_version": "${local.version}",
            "template_description": "Promoted via OpenTofu from Git"
          },
          "git_import_info": {
            "branch_name": "${var.github_branch}",
            "file_path": "${var.template_yaml_path}",
            "connector_ref": "${var.git_connector_ref}",
            "repo_name": "${var.github_repo}",
            "is_force_import": true
          }
        }'
    EOT
  }
}

# =============================================================================
# Fallback: Create template inline (no git backing) when connector is not set
# =============================================================================

resource "harness_platform_template" "project" {
  count         = var.is_project_scope && !local.use_git_backend ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  project_id    = var.project_id
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}

resource "harness_platform_template" "org" {
  count         = var.is_org_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}

resource "harness_platform_template" "account" {
  count         = var.is_account_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}
