# =============================================================================
# Outputs
# =============================================================================

output "promotion_scope" {
  description = "Resolved promotion scope based on the variables provided."
  value = (
    var.target_project_id != "" ? "project" :
    var.target_org_id     != "" ? "org"     :
    "account"
  )
}

output "template_already_exists" {
  description = "Whether the template already exists in the target project."
  value       = local.template_already_exists
}

output "template_status" {
  description = "Human-readable status of the template promotion."
  value = (
    local.template_already_exists
    ? "SKIPPED — Template '${local.template_identifier}' already exists in project '${var.target_project_id}'. No action taken."
    : local.should_create_template
      ? "CREATED — Template '${local.template_identifier}' promoted to project '${var.target_project_id}'."
      : "DISABLED — Template promotion is disabled (promote_template = false)."
  )
}

output "template_identifier" {
  description = "Harness identifier of the promoted template (if applicable)."
  value       = local.should_create_template ? module.harness_template[0].template_identifier : local.template_identifier
}

output "template_version_label" {
  description = "Version label of the promoted template (if applicable)."
  value       = local.should_create_template ? module.harness_template[0].template_version_label : null
}

output "template_git_source" {
  description = "GitHub source URL the promoted template was read from."
  value       = local.should_create_template ? module.harness_template[0].git_source_url : null
}

output "opa_policy_identifier" {
  description = "Harness identifier of the promoted OPA policy (if applicable)."
  value       = var.promote_opa ? module.harness_opa[0].policy_identifier : null
}

output "opa_git_source" {
  description = "GitHub source URL the promoted OPA policy was read from."
  value       = var.promote_opa ? module.harness_opa[0].git_source_url : null
}
