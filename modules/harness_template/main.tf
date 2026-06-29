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
}

# =============================================================================
# Import template from Git (git-backed) using Harness API
# This registers the template in Harness pointing to the existing YAML file
# in the Git repo — it does NOT create a new file.
# =============================================================================

resource "terraform_data" "import_template" {
  count = var.is_project_scope && local.use_git_backend ? 1 : 0

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
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Step 1: Get current file from GitHub
      FILE_RESPONSE=$(curl -s \
        -H "Authorization: token ${var.github_token}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/contents/${var.template_yaml_path}?ref=${var.github_branch}")

      FILE_SHA=$(echo "$FILE_RESPONSE" | jq -r '.sha')
      echo "$FILE_RESPONSE" | jq -r '.content' | base64 -d > /tmp/template_original.yaml

      echo "=== Original YAML (first 5 lines) ==="
      head -5 /tmp/template_original.yaml

      # Step 2: Update projectIdentifier and orgIdentifier in the YAML
      if grep -q "projectIdentifier:" /tmp/template_original.yaml; then
        sed -i "s/projectIdentifier:.*/projectIdentifier: ${var.project_id}/" /tmp/template_original.yaml
      else
        sed -i "/type: Stage/a\\  projectIdentifier: ${var.project_id}" /tmp/template_original.yaml
      fi

      if grep -q "orgIdentifier:" /tmp/template_original.yaml; then
        sed -i "s/orgIdentifier:.*/orgIdentifier: ${var.org_id}/" /tmp/template_original.yaml
      else
        sed -i "/projectIdentifier:/a\\  orgIdentifier: ${var.org_id}" /tmp/template_original.yaml
      fi

      echo "=== Updated YAML (first 7 lines) ==="
      head -7 /tmp/template_original.yaml

      # Step 3: Push updated file to Git
      NEW_CONTENT=$(base64 -w 0 /tmp/template_original.yaml)
      UPDATE_RESPONSE=$(curl -s -w "\n%%{http_code}" -X PUT \
        -H "Authorization: token ${var.github_token}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${var.github_owner}/${var.github_repo}/contents/${var.template_yaml_path}" \
        -d "{\"message\":\"chore: update template identifiers for ${var.project_id}\",\"content\":\"$NEW_CONTENT\",\"sha\":\"$FILE_SHA\",\"branch\":\"${var.github_branch}\"}")
      UPDATE_CODE=$(echo "$UPDATE_RESPONSE" | tail -1)
      echo "Git update status: $UPDATE_CODE"
      if [ "$UPDATE_CODE" -ge 400 ]; then
        echo "ERROR: Failed to update file in Git"
        echo "$UPDATE_RESPONSE" | sed '$d'
        exit 1
      fi

      # Step 4: Wait for Git to propagate
      sleep 5

      # Step 5: Import the template from Git into Harness
      RESPONSE=$(curl -s -w "\n%%{http_code}" -X POST \
        "${var.harness_endpoint}/v1/orgs/${var.org_id}/projects/${var.project_id}/templates/${local.identifier}/import" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Harness-Account: ${var.account_id}" \
        -H "Content-Type: application/json" \
        -d '{
          "git_import_details": {
            "connector_ref": "${var.git_connector_ref}",
            "repo_name": "${var.github_repo}",
            "branch_name": "${var.github_branch}",
            "file_path": "${var.template_yaml_path}",
            "is_force_import": true
          },
          "template_import_request": {
            "template_name": "${local.name}",
            "template_version": "${local.version}",
            "template_description": "Promoted via OpenTofu from Git"
          }
        }')
      HTTP_CODE=$(echo "$RESPONSE" | tail -1)
      BODY=$(echo "$RESPONSE" | sed '$d')
      echo "Import HTTP Status: $HTTP_CODE"
      echo "Import Response: $BODY"
      if [ "$HTTP_CODE" -ge 400 ]; then
        echo "ERROR: Import API failed with status $HTTP_CODE"
        exit 1
      fi
      echo "SUCCESS: Template imported into ${var.project_id}"
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
  count         = var.is_org_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  org_id        = var.org_id
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}

resource "harness_platform_template" "account" {
  count         = var.is_account_scope ? 1 : 0
  identifier    = local.identifier
  name          = local.name
  version       = local.version
  is_stable     = true
  template_yaml = yamlencode(var.template_spec)
}
