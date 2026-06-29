locals {
  spec        = var.opa_spec != null ? var.opa_spec : {}
  name        = try(local.spec.name,       "promoted-opa-policy")
  identifier  = try(local.spec.identifier, replace(local.name, " ", "_"))
  rego        = try(local.spec.rego,       try(local.spec.policy, ""))
  description = "Promoted by OpenTofu from: ${var.git_source_url}"
}
resource "harness_platform_policy" "project" {
  count       = var.is_project_scope ? 1 : 0
  identifier  = local.identifier
  name        = local.name
  rego        = local.rego
  org_id      = var.org_id
  project_id  = var.project_id
  description = local.description
}
resource "harness_platform_policy" "org" {
  count       = var.is_org_scope ? 1 : 0
  identifier  = local.identifier
  name        = local.name
  rego        = local.rego
  org_id      = var.org_id
  description = local.description
}
resource "harness_platform_policy" "account" {
  count       = var.is_account_scope ? 1 : 0
  identifier  = local.identifier
  name        = local.name
  rego        = local.rego
  description = local.description
}
