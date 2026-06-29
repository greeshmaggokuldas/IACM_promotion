variable "account_id" {
  type = string
}

variable "org_id" {
  type    = string
  default = ""
}

variable "project_id" {
  type    = string
  default = ""
}

variable "is_project_scope" {
  type = bool
}

variable "is_org_scope" {
  type = bool
}

variable "is_account_scope" {
  type = bool
}

variable "template_spec" {
  type = any
}

variable "git_source_url" {
  type = string
}

variable "git_connector_ref" {
  type    = string
  default = ""
}

variable "github_repo" {
  type    = string
  default = ""
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "template_yaml_path" {
  type    = string
  default = "template.yaml"
}

variable "harness_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "harness_endpoint" {
  type    = string
  default = "https://app.harness.io"
}
