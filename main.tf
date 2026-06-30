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

# -- template.yaml (optional — only used when promote_type = "template") --
data "github_repository_file" "template_yaml" {
  count      = local.do_template ? 1 : 0
  repository = var.github_repo
  branch     = var.github_branch
  file       = var.template_yaml_path   # e.g. "templates/template.yaml"
}

# -- OPA rego file (optional — only used when promote_type = "opa") --
data "github_repository_file" "opa_yaml" {
  count      = local.do_opa ? 1 : 0
  repository = var.github_repo
  branch     = var.github_branch
  file       = var.opa_yaml_path        # e.g. ".harness/OPA/policy.rego"
}

# =============================================================================
# 2. Parse the YAML payloads
# =============================================================================

locals {
  # Determine what to promote based on promote_type
  do_template = var.promote_type == "template"
  do_opa      = var.promote_type == "opa"

  # Raw content from GitHub (may be null or empty)
  template_raw = local.do_template ? try(data.github_repository_file.template_yaml[0].content, "") : ""
  opa_raw      = local.do_opa ? try(data.github_repository_file.opa_yaml[0].content, "") : ""

  # Decoded template spec (null when not promoting or content is empty)
  template_spec = local.do_template && local.template_raw != null && trimspace(local.template_raw) != "" ? yamldecode(local.template_raw) : null

  # Decoded OPA spec — for .rego files, just pass as raw string (not YAML)
  opa_spec = local.do_opa && local.opa_raw != null && trimspace(local.opa_raw) != "" ? { "rego" = local.opa_raw } : null

  # Extract template identifier from the YAML spec for the existence check
  template_identifier = local.do_template ? try(
    local.template_spec.template.identifier,
    try(local.template_spec.identifier, replace(try(local.template_spec.template.name, try(local.template_spec.name, "promoted-template")), " ", "_"))
  ) : ""

  # Canonical git source URL that will be stored on the promoted resource
  # so the created artifact remains git-backed and traceable to its origin.
  git_source_url = "https://github.com/${var.github_owner}/${var.github_repo}/blob/${var.github_branch}"

  template_git_source = local.do_template ? "${local.git_source_url}/${var.template_yaml_path}" : null
  opa_git_source      = local.do_opa      ? "${local.git_source_url}/${var.opa_yaml_path}"      : null

  # Scope helpers — used by child modules to decide which Harness resource type to create
  is_project_scope = var.target_project_id != null && var.target_project_id != ""
  is_org_scope     = !local.is_project_scope && var.target_org_id != null && var.target_org_id != ""
  is_account_scope = !local.is_project_scope && !local.is_org_scope
}

# =============================================================================
# 2b. Check if template already exists in the target project
# =============================================================================

# Note: We use the Harness template list API with a version query param.
# OpenTofu's http provider HTML-encodes '&' in URLs, so we use a single
# query parameter approach via the v1 API which uses path-based routing.

data "http" "check_template_exists" {
  count = local.do_template && local.is_project_scope && local.template_spec != null ? 1 : 0

  url    = "${var.harness_endpoint}/v1/orgs/${var.target_org_id}/projects/${var.target_project_id}/templates/${local.template_identifier}"
  method = "GET"

  request_headers = {
    x-api-key        = var.harness_api_key
    Harness-Account  = var.harness_account_id
    Content-Type     = "application/json"
  }
}

locals {
  # Template exists if the API returns 200; treat any other response as "does not exist"
  template_already_exists = (
    local.do_template && local.is_project_scope && local.template_spec != null
    ? try(data.http.check_template_exists[0].status_code == 200, false)
    : false
  )

  # Only proceed with creation if template does NOT already exist AND spec is valid
  should_create_template = local.do_template && !local.template_already_exists && local.template_spec != null
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

  # Git-connector to keep the promoted template git-backed (import from git)
  git_connector_ref = var.harness_git_connector_ref
  github_repo       = var.github_repo
  github_branch     = var.github_branch
  template_yaml_path = var.template_yaml_path

  # API credentials for import API call
  harness_api_key   = var.harness_api_key
  harness_endpoint  = var.harness_endpoint
  github_token      = var.github_token
  github_owner      = var.github_owner
}

# =============================================================================
# 4. OPA Policy Promotion Module (git-backed import)
# =============================================================================

module "harness_opa" {
  count  = local.do_opa ? 1 : 0
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

  # Git-backed import settings
  git_connector_ref  = var.harness_git_connector_ref
  github_repo        = var.github_repo
  github_branch      = var.github_branch
  github_token       = var.github_token
  github_owner       = var.github_owner
  opa_file_path      = var.opa_yaml_path
  harness_api_key    = var.harness_api_key
  harness_endpoint   = var.harness_endpoint
  opa_policy_name    = var.opa_policy_name
  opa_policy_identifier = var.opa_policy_identifier
}
