# =============================================================================
# Harness Template / OPA Promotion Pipeline
# OpenTofu script to promote template.yaml or OPA.yaml from a GitHub source
# into a target Harness project, org, or account — determined by API key scope.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.31"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# -----------------------------------------------------------------------------
# Harness Provider
# The scope (project / org / account) is determined purely by which API key
# you supply.  No code changes are needed — just change var.harness_api_key
# and set the matching var.target_org_id / var.target_project_id.
# -----------------------------------------------------------------------------
provider "harness" {
  endpoint         = var.harness_endpoint
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}

# -----------------------------------------------------------------------------
# GitHub Provider  (reads the source YAML files)
# -----------------------------------------------------------------------------
provider "github" {
  token = var.github_token
  owner = var.github_owner
}

# =============================================================================
# 1. Read source YAML files from GitHub
# =============================================================================

# -- template.yaml (optional — only used when var.promote_template = true) --
data "github_repository_file" "template_yaml" {
  count      = var.promote_template ? 1 : 0
  repository = var.github_repo
  branch     = var.github_branch
  file       = var.template_yaml_path   # e.g. "templates/template.yaml"
}

# -- OPA.yaml (optional — only used when var.promote_opa = true) --
data "github_repository_file" "opa_yaml" {
  count      = var.promote_opa ? 1 : 0
  repository = var.github_repo
  branch     = var.github_branch
  file       = var.opa_yaml_path        # e.g. "opa/OPA.yaml"
}

# =============================================================================
# 2. Parse the YAML payloads
# =============================================================================

locals {
  # Raw content from GitHub (may be null or empty)
  template_raw = var.promote_template ? try(data.github_repository_file.template_yaml[0].content, "") : ""
  opa_raw      = var.promote_opa ? try(data.github_repository_file.opa_yaml[0].content, "") : ""

  # Decoded template spec (null when not promoting or content is empty)
  template_spec = var.promote_template && local.template_raw != null && trimspace(local.template_raw) != "" ? yamldecode(local.template_raw) : null

  # Decoded OPA spec (null when not promoting or content is empty)
  opa_spec = var.promote_opa && local.opa_raw != null && trimspace(local.opa_raw) != "" ? yamldecode(local.opa_raw) : null

  # Extract template identifier from the YAML spec for the existence check
  template_identifier = var.promote_template ? try(
    local.template_spec.template.identifier,
    try(local.template_spec.identifier, replace(try(local.template_spec.template.name, try(local.template_spec.name, "promoted-template")), " ", "_"))
  ) : ""

  # Canonical git source URL that will be stored on the promoted resource
  # so the created artifact remains git-backed and traceable to its origin.
  git_source_url = "https://github.com/${var.github_owner}/${var.github_repo}/blob/${var.github_branch}"

  template_git_source = var.promote_template ? "${local.git_source_url}/${var.template_yaml_path}" : null
  opa_git_source      = var.promote_opa      ? "${local.git_source_url}/${var.opa_yaml_path}"      : null

  # Scope helpers — used by child modules to decide which Harness resource type to create
  is_project_scope = var.target_project_id != null && var.target_project_id != ""
  is_org_scope     = !local.is_project_scope && var.target_org_id != null && var.target_org_id != ""
  is_account_scope = !local.is_project_scope && !local.is_org_scope
}

# =============================================================================
# 2b. Check if template already exists in the target project
# =============================================================================

data "http" "check_template_exists" {
  count = var.promote_template && local.is_project_scope ? 1 : 0

  url = join("", [
    var.harness_endpoint,
    "/template/api/templates/",
    local.template_identifier,
    "?accountIdentifier=", var.harness_account_id,
    "&orgIdentifier=", var.target_org_id,
    "&projectIdentifier=", var.target_project_id,
    "&getDefaultFromOtherRepo=true"
  ])

  method = "GET"

  request_headers = {
    x-api-key    = var.harness_api_key
    Content-Type = "application/json"
  }

  # Don't fail if template doesn't exist (404) or API returns bad request (400)
  lifecycle {
    postcondition {
      condition     = contains([200, 404, 400], self.status_code)
      error_message = "Unexpected response from Harness API: ${self.status_code}"
    }
  }
}

locals {
  # Template exists if the API returns 200
  template_already_exists = (
    var.promote_template && local.is_project_scope
    ? try(data.http.check_template_exists[0].status_code == 200, false)
    : false
  )

  # Only proceed with creation if template does NOT already exist AND spec is valid
  should_create_template = var.promote_template && !local.template_already_exists && local.template_spec != null
}

# =============================================================================
# 3. Template Promotion Module
# =============================================================================

module "harness_template" {
  count  = local.should_create_template ? 1 : 0
  source = "./modules/harness_template"

  # Harness targeting
  account_id  = var.harness_account_id
  org_id      = var.target_org_id
  project_id  = var.target_project_id

  # Scope flags (derived)
  is_project_scope = local.is_project_scope
  is_org_scope     = local.is_org_scope
  is_account_scope = local.is_account_scope

  # Template content from GitHub
  template_spec   = local.template_spec
  git_source_url  = local.template_git_source

  # Git-connector to keep the promoted template git-backed
  git_connector_ref = var.harness_git_connector_ref
  github_repo       = var.github_repo
  github_branch     = var.github_branch
  template_yaml_path = var.template_yaml_path
}

# =============================================================================
# 4. OPA Policy Promotion Module
# =============================================================================

module "harness_opa" {
  count  = var.promote_opa && local.opa_spec != null ? 1 : 0
  source = "./modules/harness_opa"

  # Harness targeting
  account_id = var.harness_account_id
  org_id     = var.target_org_id
  project_id = var.target_project_id

  # Scope flags (derived)
  is_project_scope = local.is_project_scope
  is_org_scope     = local.is_org_scope
  is_account_scope = local.is_account_scope

  # OPA content from GitHub
  opa_spec       = local.opa_spec
  git_source_url = local.opa_git_source
}
