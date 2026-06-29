terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.31"
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
  spec_yaml  = yamlencode(var.template_spec)
  use_git_backend = var.git_connector_ref != ""
}

resource "harness_platform_template" "project" {
  count         = var.is_project_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  project_id    = var.project_id
  is_stable     = true
  template_yaml = local.spec_yaml

  dynamic "git_details" {
    for_each = local.use_git_backend ? [1] : []
    content {
      branch_name    = var.github_branch
      commit_message = "chore: promote ${local.identifier} v${local.version} via OpenTofu"
      file_path      = var.template_yaml_path
      connector_ref  = var.git_connector_ref
      store_type     = "REMOTE"
      repo_name      = var.github_repo
    }
  }
}

resource "harness_platform_template" "org" {
  count         = var.is_org_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  is_stable     = true
  template_yaml = local.spec_yaml

  dynamic "git_details" {
    for_each = local.use_git_backend ? [1] : []
    content {
      branch_name    = var.github_branch
      commit_message = "chore: promote ${local.identifier} v${local.version} via OpenTofu"
      file_path      = var.template_yaml_path
      connector_ref  = var.git_connector_ref
      store_type     = "REMOTE"
      repo_name      = var.github_repo
    }
  }
}

resource "harness_platform_template" "account" {
  count         = var.is_account_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  is_stable     = true
  template_yaml = local.spec_yaml

  dynamic "git_details" {
    for_each = local.use_git_backend ? [1] : []
    content {
      branch_name    = var.github_branch
      commit_message = "chore: promote ${local.identifier} v${local.version} via OpenTofu"
      file_path      = var.template_yaml_path
      connector_ref  = var.git_connector_ref
      store_type     = "REMOTE"
      repo_name      = var.github_repo
    }
  }
}
