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
# File path inside the repo (used for both template and OPA)
# -----------------------------------------------------------------------------
variable "resource_path" {
  description = "Path to the resource file inside the repository. For templates: path to YAML (e.g. .harness/gitops_sync_template_v1.yaml). For OPA: path to .rego file (e.g. .harness/OPA/policy.rego)."
  type        = string
}

# -----------------------------------------------------------------------------
# What to promote (dropdown: "template" or "opa")
# -----------------------------------------------------------------------------
variable "promote_type" {
  description = "Type of resource to promote: 'template' or 'opa'."
  type        = string
  default     = "template"

  validation {
    condition     = contains(["template", "opa"], var.promote_type)
    error_message = "promote_type must be either 'template' or 'opa'."
  }
}

# -----------------------------------------------------------------------------
# OPA policy settings
# -----------------------------------------------------------------------------
variable "opa_policy_name" {
  description = "Name for the OPA policy in Harness (extracted from file if not set)."
  type        = string
  default     = ""
}

variable "opa_policy_identifier" {
  description = "Identifier for the OPA policy in Harness (derived from name if not set)."
  type        = string
  default     = ""
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
