locals {
  _policy = (
    var.is_project_scope ? try(harness_platform_policy.project[0], null) :
    var.is_org_scope     ? try(harness_platform_policy.org[0],     null) :
                           try(harness_platform_policy.account[0], null)
  )
}
output "policy_identifier" { value = try(local._policy.identifier, null) }
output "git_source_url"    { value = var.git_source_url }
