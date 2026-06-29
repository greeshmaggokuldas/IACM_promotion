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

output "template_identifier" {
  description = "Harness identifier of the promoted template (if applicable)."
  value       = var.promote_template ? module.harness_template[0].template_identifier : null
}

output "template_version_label" {
  description = "Version label of the promoted template (if applicable)."
  value       = var.promote_template ? module.harness_template[0].template_version_label : null
}

output "template_git_source" {
  description = "GitHub source URL the promoted template was read from."
  value       = var.promote_template ? module.harness_template[0].git_source_url : null
}

output "opa_policy_identifier" {
  description = "Harness identifier of the promoted OPA policy (if applicable)."
  value       = var.promote_opa ? module.harness_opa[0].policy_identifier : null
}

output "opa_git_source" {
  description = "GitHub source URL the promoted OPA policy was read from."
  value       = var.promote_opa ? module.harness_opa[0].git_source_url : null
}
