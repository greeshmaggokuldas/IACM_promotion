# =============================================================================
# Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Harness connection
# -----------------------------------------------------------------------------
variable "harness_endpoint" {
  description = "Harness NG API endpoint."
  type        = string
  default     = "https://app.harness.io"
}

variable "harness_account_id" {
  description = "Harness Account ID (always required)."
  type        = string
}

variable "harness_api_key" {
  description = <<-EOT
    Harness Personal Access Token or Service Account token.
    The SCOPE of this key determines where resources are created:
      - Project-scoped token  → promotes into the specified project
      - Org-scoped token      → promotes at org level (set target_project_id = "")
      - Account-scoped token  → promotes at account level (set both org/project = "")
  EOT
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Promotion target (scope is inferred from which values are set)
# -----------------------------------------------------------------------------
variable "target_org_id" {
  description = "Harness Org ID to promote into. Leave empty for account-level promotion."
  type        = string
  default     = ""
}

variable "target_project_id" {
  description = "Harness Project ID to promote into. Leave empty for org or account-level promotion."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# GitHub source (where template.yaml / OPA.yaml live)
# -----------------------------------------------------------------------------
variable "github_token" {
  description = "GitHub Personal Access Token with repo read access."
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the source repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without owner prefix)."
  type        = string
}

variable "github_branch" {
  description = "Branch to read the YAML files from."
  type        = string
  default     = "main"
}

# -----------------------------------------------------------------------------
# File paths inside the repo
# -----------------------------------------------------------------------------
variable "template_yaml_path" {
  description = "Path to template.yaml inside the repository (e.g. templates/template.yaml)."
  type        = string
  default     = "template.yaml"
}

variable "opa_yaml_path" {
  description = "Path to OPA.yaml inside the repository (e.g. opa/OPA.yaml)."
  type        = string
  default     = "OPA.yaml"
}

# -----------------------------------------------------------------------------
# What to promote
# -----------------------------------------------------------------------------
variable "promote_template" {
  description = "Set to true to promote the Harness Pipeline Template."
  type        = bool
  default     = true
}

variable "promote_opa" {
  description = "Set to true to promote the OPA Policy."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Git connector (keeps the promoted template git-backed in Harness)
# -----------------------------------------------------------------------------
variable "harness_git_connector_ref" {
  description = <<-EOT
    Ref of the Harness Git Connector that points to the source GitHub repo.
    Used so that the promoted template stays git-backed inside Harness.
    Format: "account.<connector_id>" | "org.<connector_id>" | "<connector_id>"
  EOT
  type        = string
  default     = ""
}
