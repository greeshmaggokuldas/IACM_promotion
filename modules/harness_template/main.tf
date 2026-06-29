terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.31"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

locals {
  spec       = var.template_spec != null ? var.template_spec : {}
  # Handle both flat structure and nested 'template:' wrapper
  inner      = try(local.spec.template, local.spec)
  name       = try(local.inner.name, "promoted-template")
  identifier = try(local.inner.identifier, replace(local.name, " ", "_"))
  version    = try(local.inner.versionLabel, "1.0.0")
  use_git_backend = var.git_connector_ref != ""

  # Determine the import API URL based on scope
  import_url = (
    var.is_project_scope
    ? "${var.harness_endpoint}/v1/orgs/${var.org_id}/projects/${var.project_id}/templates/${local.identifier}/import"
    : var.is_org_scope
      ? "${var.harness_endpoint}/v1/orgs/${var.org_id}/templates/${local.identifier}/import"
      : "${var.harness_endpoint}/v1/templates/${local.identifier}/import"
  )

  # Scope label for logging
  scope_label = (
    var.is_project_scope ? "${var.org_id}/${var.project_id}"
    : var.is_org_scope   ? "${var.org_id} (org-level)"
    : "account-level"
  )
}

# =============================================================================
# Import template from Git (git-backed) using Harness API
# Supports project, org, and account level imports.
# Updates the YAML in Git with correct scope identifiers, then imports.
# =============================================================================

resource "terraform_data" "import_template" {
  count = local.use_git_backend ? 1 : 0

  # Re-run every time by using a timestamp trigger
  triggers_replace = [timestamp()]

  input = {
    identifier  = local.identifier
    name        = local.name
    version     = local.version
    org_id      = var.org_id
    project_id  = var.project_id
    connector   = var.git_connector_ref
    repo        = var.github_repo
    branch      = var.github_branch
    file_path   = var.template_yaml_path
    scope       = var.is_project_scope ? "project" : var.is_org_scope ? "org" : "account"
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

      echo "=== Promotion Scope: ${local.scope_label} ==="

      # Step 1: Get file SHA and download raw content
      FILE_META=$(curl -s \
        -H "Authorization: token ${var.github_token}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/contents/${var.template_yaml_path}?ref=${var.github_branch}")
      FILE_SHA=$(echo "$FILE_META" | jq -r '.sha')
      echo "Current file SHA: $FILE_SHA"

      # Download raw content
      curl -sL \
        -H "Authorization: token ${var.github_token}" \
        -H "Accept: application/vnd.github.v3.raw" \
        "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/contents/${var.template_yaml_path}?ref=${var.github_branch}" \
        -o /tmp/template.yaml

      echo "=== Downloaded YAML (first 6 lines) ==="
      head -6 /tmp/template.yaml

      # Step 2: Update scope identifiers based on target scope
      # First, remove any existing projectIdentifier and orgIdentifier lines
      sed -i '/^  projectIdentifier:/d' /tmp/template.yaml
      sed -i '/^  orgIdentifier:/d' /tmp/template.yaml

      # Now add the correct ones based on scope (after 'type: Stage' line)
      if [ "${var.is_project_scope}" = "true" ]; then
        # Project scope: needs both orgIdentifier and projectIdentifier
        sed -i "/  type: Stage/a\\  projectIdentifier: ${var.project_id}" /tmp/template.yaml
        sed -i "/  projectIdentifier:/a\\  orgIdentifier: ${var.org_id}" /tmp/template.yaml
      elif [ "${var.is_org_scope}" = "true" ]; then
        # Org scope: needs only orgIdentifier, no projectIdentifier
        sed -i "/  type: Stage/a\\  orgIdentifier: ${var.org_id}" /tmp/template.yaml
      fi
      # Account scope: no orgIdentifier or projectIdentifier needed

      echo "=== Updated YAML (first 10 lines) ==="
      head -10 /tmp/template.yaml

      # Step 3: Validate YAML is not empty/corrupt
      if [ ! -s /tmp/template.yaml ]; then
        echo "ERROR: Template YAML is empty!"
        exit 1
      fi
      LINECOUNT=$(wc -l < /tmp/template.yaml)
      echo "YAML line count: $LINECOUNT"
      if [ "$LINECOUNT" -lt 10 ]; then
        echo "ERROR: Template YAML seems truncated (only $LINECOUNT lines)"
        exit 1
      fi

      # Step 4: Push to Git
      NEW_CONTENT=$(base64 -w 0 < /tmp/template.yaml)
      PAYLOAD=$(jq -n \
        --arg msg "chore: set template scope to ${local.scope_label}" \
        --arg content "$NEW_CONTENT" \
        --arg sha "$FILE_SHA" \
        --arg branch "${var.github_branch}" \
        '{message: $msg, content: $content, sha: $sha, branch: $branch}')

      UPDATE_CODE=$(curl -s -o /tmp/git_response.json -w "%%{http_code}" -X PUT \
        -H "Authorization: token ${var.github_token}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/contents/${var.template_yaml_path}" \
        -d "$PAYLOAD")
      echo "Git push status: $UPDATE_CODE"
      if [ "$UPDATE_CODE" -ge 400 ]; then
        echo "ERROR: Git push failed"
        cat /tmp/git_response.json
        exit 1
      fi

      # Step 5: Wait for Harness connector cache to refresh
      echo "Waiting 20s for Harness to pick up new commit..."
      sleep 20

      # Step 6: Import template from Git into Harness
      IMPORT_CODE=$(curl -s -o /tmp/import_response.json -w "%%{http_code}" -X POST \
        "${local.import_url}" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Harness-Account: ${var.account_id}" \
        -H "Content-Type: application/json" \
        -d "{\"git_import_details\":{\"connector_ref\":\"${var.git_connector_ref}\",\"repo_name\":\"${var.github_repo}\",\"branch_name\":\"${var.github_branch}\",\"file_path\":\"${var.template_yaml_path}\",\"is_force_import\":true},\"template_import_request\":{\"template_name\":\"${local.name}\",\"template_version\":\"${local.version}\",\"template_description\":\"Promoted via OpenTofu\"}}")
      echo "Import status: $IMPORT_CODE"
      cat /tmp/import_response.json
      echo ""
      if [ "$IMPORT_CODE" -ge 400 ]; then
        echo "ERROR: Harness import failed with status $IMPORT_CODE"
        exit 1
      fi
      echo "SUCCESS: Template '${local.identifier}' imported at scope: ${local.scope_label}"
    EOT
  }
}

# =============================================================================
# Fallback: Create template inline (no git backing) when connector is not set
# =============================================================================

resource "harness_platform_template" "project" {
  count         = var.is_project_scope && !local.use_git_backend ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  project_id    = var.project_id
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}

resource "harness_platform_template" "org" {
  count         = var.is_org_scope && !local.use_git_backend ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}

resource "harness_platform_template" "account" {
  count         = var.is_account_scope && !local.use_git_backend ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}
