locals {
  _resource = (
    var.is_project_scope && !local.use_git_backend ? try(harness_platform_template.project[0], null) :
    var.is_org_scope     ? try(harness_platform_template.org[0], null) :
    var.is_account_scope ? try(harness_platform_template.account[0], null) :
    null
  )
}

output "template_identifier" {
  value = local.use_git_backend ? local.identifier : try(local._resource.identifier, local.identifier)
}

output "template_version_label" {
  value = local.use_git_backend ? local.version : try(local._resource.version, local.version)
}

output "git_source_url" {
  value = var.git_source_url
}
