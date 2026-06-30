# =============================================================================
# Outputs
# =============================================================================

output "promote_type" {
  description = "Type of resource being promoted."
  value       = var.promote_type
}

output "promotion_scope" {
  description = "Resolved promotion scope based on the variables provided."
  value = (
    var.target_project_id != "" ? "project" :
    var.target_org_id     != "" ? "org"     :
    "account"
  )
}

# --- Template outputs ---

output "template_already_exists" {
  description = "Whether the template already exists in the target project."
  value       = local.do_template ? local.template_already_exists : null
}

output "template_status" {
  description = "Human-readable status of the template promotion."
  value = local.do_template ? (
    local.template_already_exists
    ? "SKIPPED — Template '${local.template_identifier}' already exists in project '${var.target_project_id}'. No action taken."
    : local.should_create_template
      ? "CREATED — Template promoted."
      : "DISABLED — Template promotion not triggered."
  ) : "N/A — promote_type is not 'template'"
}

output "template_identifier" {
  description = "Harness identifier of the promoted template (if applicable)."
  value       = local.do_template && local.should_create_template ? module.harness_template[0].template_identifier : local.template_identifier
}

# --- OPA outputs ---

output "opa_policy_identifier" {
  description = "Harness identifier of the promoted OPA policy (if applicable)."
  value       = local.do_opa ? module.harness_opa[0].policy_identifier : null
}

output "opa_git_source" {
  description = "GitHub source URL the promoted OPA policy was read from."
  value       = local.do_opa ? module.harness_opa[0].git_source_url : null
}
