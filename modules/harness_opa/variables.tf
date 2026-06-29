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

variable "opa_spec" {
  type = any
}

variable "git_source_url" {
  type = string
}
