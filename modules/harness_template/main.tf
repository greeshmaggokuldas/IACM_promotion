locals {
  spec       = var.template_spec != null ? var.template_spec : {}
  name       = try(local.spec.name,         "promoted-template")
  identifier = try(local.spec.identifier,   replace(local.name, " ", "_"))
  version    = try(local.spec.versionLabel, "1.0.0")
  spec_yaml  = yamlencode(var.template_spec)
  description      = "Promoted by OpenTofu from: ${var.git_source_url}"
  use_git_backend  = var.git_connector_ref != ""
}
resource "harness_platform_template" "project" {
  count         = var.is_project_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  project_id    = var.project_id
  description   = local.description
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
  description   = local.description
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
  description   = local.description
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
