locals {
  _resource = (
    var.is_project_scope ? try(harness_platform_template.project[0], null) :
    var.is_org_scope     ? try(harness_platform_template.org[0],     null) :
                           try(harness_platform_template.account[0], null)
  )
}
output "template_identifier"    { value = try(local._resource.identifier, null) }
output "template_version_label" { value = try(local._resource.version,    null) }
output "git_source_url"         { value = var.git_source_url }
