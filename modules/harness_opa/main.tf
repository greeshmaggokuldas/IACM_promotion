terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.31"
    }
  }
}

locals {
  spec       = var.opa_spec != null ? var.opa_spec : {}
  name       = var.opa_policy_name != "" ? var.opa_policy_name : try(local.spec.name, replace(basename(var.opa_file_path), ".rego", ""))
  identifier = var.opa_policy_identifier != "" ? var.opa_policy_identifier : try(local.spec.identifier, replace(local.name, "-", "_"))
  use_git_backend = var.git_connector_ref != ""

  # Determine the create API URL based on scope (no identifier in path for POST)
  import_url = (
    var.is_project_scope
    ? "${var.harness_endpoint}/pm/api/v1/policies?accountIdentifier=${var.account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}"
    : var.is_org_scope
      ? "${var.harness_endpoint}/pm/api/v1/policies?accountIdentifier=${var.account_id}&orgIdentifier=${var.org_id}"
      : "${var.harness_endpoint}/pm/api/v1/policies?accountIdentifier=${var.account_id}"
  )

  # Scope label for logging
  scope_label = (
    var.is_project_scope ? "${var.org_id}/${var.project_id}"
    : var.is_org_scope   ? "${var.org_id} (org-level)"
    : "account-level"
  )
}

# =============================================================================
# Import OPA policy from Git (git-backed) using Harness API
# OPA policies are .rego files — no projectIdentifier/orgIdentifier inside.
# Scope is determined purely by the API endpoint.
# =============================================================================

resource "terraform_data" "import_opa_policy" {
  count = local.use_git_backend ? 1 : 0

  # Re-run every time
  triggers_replace = [timestamp()]

  input = {
    identifier = local.identifier
    name       = local.name
    org_id     = var.org_id
    project_id = var.project_id
    connector  = var.git_connector_ref
    repo       = var.github_repo
    branch     = var.github_branch
    file_path  = var.opa_file_path
    scope      = var.is_project_scope ? "project" : var.is_org_scope ? "org" : "account"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Install jq if not available
      if ! command -v jq &> /dev/null; then
        echo "Installing jq..."
        curl -sL -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
        chmod +x /usr/local/bin/jq
      fi

      echo "=== OPA Policy Promotion ==="
      echo "Scope: ${local.scope_label}"
      echo "Policy: ${local.identifier}"
      echo "File: ${var.opa_file_path}"

      # Read the rego file content from GitHub
      REGO_CONTENT=$(curl -sL \
        -H "Authorization: token ${var.github_token}" \
        -H "Accept: application/vnd.github.v3.raw" \
        "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/contents/${var.opa_file_path}?ref=${var.github_branch}")

      echo "=== Rego file (first 5 lines) ==="
      echo "$REGO_CONTENT" | head -5

      if [ -z "$REGO_CONTENT" ]; then
        echo "ERROR: Rego file is empty or not found!"
        exit 1
      fi

      # Create OPA policy via Harness API with git-backed configuration
      # The PM API creates the policy and links it to Git
      ESCAPED_REGO=$(echo "$REGO_CONTENT" | jq -Rs .)

      PAYLOAD=$(jq -n \
        --arg name "${local.name}" \
        --arg identifier "${local.identifier}" \
        --argjson rego "$ESCAPED_REGO" \
        --arg connector "${var.git_connector_ref}" \
        --arg repo "${var.github_repo}" \
        --arg branch "${var.github_branch}" \
        --arg filepath "${var.opa_file_path}" \
        '{
          "identifier": $identifier,
          "name": $name,
          "rego": $rego,
          "git_connector_ref": $connector,
          "git_repo": $repo,
          "git_branch": $branch,
          "git_path": $filepath
        }')

      # Build URL - write to file to avoid any encoding issues
      echo -n "https://app.harness.io/pm/api/v1/policies?accountIdentifier=${var.account_id}" > /tmp/api_url.txt
      echo -n "&orgIdentifier=${var.org_id}" >> /tmp/api_url.txt
      if [ "${var.is_project_scope}" = "true" ]; then
        echo -n "&projectIdentifier=${var.project_id}" >> /tmp/api_url.txt
      fi
      echo -n "&git_branch=${var.github_branch}" >> /tmp/api_url.txt
      echo -n "&git_connector_ref=${var.git_connector_ref}" >> /tmp/api_url.txt
      echo -n "&git_repo=${var.github_repo}" >> /tmp/api_url.txt
      echo -n "&git_path=${var.opa_file_path}" >> /tmp/api_url.txt
      echo -n "&git_commit_msg=promote_opa_policy" >> /tmp/api_url.txt
      echo -n "&git_is_new_file=false" >> /tmp/api_url.txt

      API_URL=$(cat /tmp/api_url.txt)
      echo "API URL: $API_URL"

      echo "=== Creating OPA Policy ==="
      RESPONSE_CODE=$(curl -s -o /tmp/opa_response.json -w "%%{http_code}" -X POST \
        "$API_URL" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

      echo "API Response Code: $RESPONSE_CODE"
      cat /tmp/opa_response.json
      echo ""

      # If 409 (conflict/already exists), try PATCH to update
      if [ "$RESPONSE_CODE" = "409" ] || [ "$RESPONSE_CODE" = "400" ]; then
        echo "Policy may already exist, attempting update..."
        echo -n "https://app.harness.io/pm/api/v1/policies/${local.identifier}?accountIdentifier=${var.account_id}" > /tmp/update_url.txt
        echo -n "&orgIdentifier=${var.org_id}" >> /tmp/update_url.txt
        if [ "${var.is_project_scope}" = "true" ]; then
          echo -n "&projectIdentifier=${var.project_id}" >> /tmp/update_url.txt
        fi
        echo -n "&git_branch=${var.github_branch}" >> /tmp/update_url.txt
        echo -n "&git_connector_ref=${var.git_connector_ref}" >> /tmp/update_url.txt
        echo -n "&git_repo=${var.github_repo}" >> /tmp/update_url.txt
        echo -n "&git_path=${var.opa_file_path}" >> /tmp/update_url.txt
        echo -n "&git_commit_msg=update_opa_policy" >> /tmp/update_url.txt
        UPDATE_URL=$(cat /tmp/update_url.txt)
        RESPONSE_CODE=$(curl -s -o /tmp/opa_response.json -w "%%{http_code}" -X PATCH \
          "$UPDATE_URL" \
          -H "x-api-key: ${var.harness_api_key}" \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD")
        echo "Update Response Code: $RESPONSE_CODE"
        cat /tmp/opa_response.json
        echo ""
      fi

      if [ "$RESPONSE_CODE" -ge 400 ]; then
        echo "ERROR: OPA policy creation/update failed with status $RESPONSE_CODE"
        exit 1
      fi

      echo "SUCCESS: OPA policy '${local.identifier}' promoted at scope: ${local.scope_label}"
    EOT
  }
}

# =============================================================================
# Fallback: Create OPA policy inline (no git backing) when connector is not set
# =============================================================================

resource "harness_platform_policy" "project" {
  count       = var.is_project_scope && !local.use_git_backend ? 1 : 0
  identifier  = local.identifier
  name        = local.name
  rego        = try(local.spec.rego, try(local.spec.policy, ""))
  org_id      = var.org_id
  project_id  = var.project_id
}

resource "harness_platform_policy" "org" {
  count       = var.is_org_scope && !local.use_git_backend ? 1 : 0
  identifier  = local.identifier
  name        = local.name
  rego        = try(local.spec.rego, try(local.spec.policy, ""))
  org_id      = var.org_id
}

resource "harness_platform_policy" "account" {
  count       = var.is_account_scope && !local.use_git_backend ? 1 : 0
  identifier  = local.identifier
  name        = local.name
  rego        = try(local.spec.rego, try(local.spec.policy, ""))
}
