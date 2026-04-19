#!/bin/bash
# Polls GitHub Security Advisories API and creates/updates issues.
#
# When sourced with --source-only, exports functions without running main.
# Required env vars (for main execution):
#   GITHUB_TOKEN — PAT with security_events and repo scope
#   CONFIG_FILE  — path to sentriage.yml
#   INITIAL_LABEL — label to apply to new issues (default: needs-triage)
set -euo pipefail

format_issue_title() {
  local repo="$1" summary="$2" ghsa_id="$3"
  echo "$repo: $summary ($ghsa_id)"
}

format_issue_body() {
  local advisory_json="$1" repo="$2"

  local ghsa_id summary description severity cve_id published_at html_url affected_versions
  ghsa_id=$(echo "$advisory_json" | jq -r '.ghsa_id')
  summary=$(echo "$advisory_json" | jq -r '.summary')
  description=$(echo "$advisory_json" | jq -r '.description')
  severity=$(echo "$advisory_json" | jq -r '.severity')
  cve_id=$(echo "$advisory_json" | jq -r '.cve_id // "N/A"')
  published_at=$(echo "$advisory_json" | jq -r '.published_at')
  html_url=$(echo "$advisory_json" | jq -r '.html_url')

  affected_versions=$(echo "$advisory_json" | jq -r '
    [.vulnerabilities[]? |
      "\(.package.name // "unknown"): \(.vulnerable_version_range // "unspecified")"
    ] | if length == 0 then "Not specified" else join("\n") end
  ')

  cat <<BODY
## Vulnerability Report

| Field | Value |
|---|---|
| **Source Repo** | $repo |
| **GHSA** | [$ghsa_id]($html_url) |
| **CVE** | $cve_id |
| **Severity** | $severity |
| **Published** | $published_at |
| **Detected** | $(date -u +"%Y-%m-%dT%H:%M:%SZ") |

### Affected Versions

$affected_versions

### Description

$description
BODY
}

ghsa_id_from_title() {
  local title="$1"
  echo "$title" | grep -oE 'GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}'
}

fetch_advisories() {
  local repo="$1"
  gh api "repos/$repo/security-advisories" \
    --header "Accept: application/vnd.github+json" \
    --paginate 2>/dev/null || echo "[]"
}

find_existing_issue() {
  local ghsa_id="$1"
  gh issue list --state all --search "$ghsa_id in:title" --json number,title --jq \
    ".[] | select(.title | contains(\"$ghsa_id\")) | .number" 2>/dev/null | head -1
}

create_issue() {
  local title="$1" body="$2" label="$3"
  gh issue create --title "$title" --body "$body" --label "$label"
}

post_update_comment() {
  local issue_number="$1" advisory_json="$2"
  local updated_at
  updated_at=$(echo "$advisory_json" | jq -r '.updated_at')
  local comment="## Advisory Updated

This advisory was updated upstream at $updated_at.

### Updated Description

$(echo "$advisory_json" | jq -r '.description')

### Updated Severity

$(echo "$advisory_json" | jq -r '.severity')"

  gh issue comment "$issue_number" --body "$comment"
}

main() {
  local config_file="${CONFIG_FILE:-sentriage.yml}"
  local initial_label="${INITIAL_LABEL:-needs-triage}"
  local output_file="${GITHUB_OUTPUT:-/dev/null}"
  local new_issues=()

  if [ ! -f "$config_file" ]; then
    echo "Error: config file not found: $config_file" >&2
    exit 1
  fi

  local config_json
  config_json=$(python3 -c "
import yaml, json, sys
with open(sys.argv[1]) as f:
    print(json.dumps(yaml.safe_load(f)))
" "$config_file")

  local repos
  repos=$(echo "$config_json" | jq -r '.monitored_repos[].repo')

  while IFS= read -r repo; do
    echo "Checking $repo for security advisories..."
    local advisories
    advisories=$(fetch_advisories "$repo")

    while IFS= read -r advisory; do
      local ghsa_id summary
      ghsa_id=$(echo "$advisory" | jq -r '.ghsa_id')
      summary=$(echo "$advisory" | jq -r '.summary')

      local existing_issue
      existing_issue=$(find_existing_issue "$ghsa_id")

      if [ -z "$existing_issue" ]; then
        echo "  New advisory: $ghsa_id — $summary"
        local title body
        title=$(format_issue_title "$repo" "$summary" "$ghsa_id")
        body=$(format_issue_body "$advisory" "$repo")
        local issue_url
        issue_url=$(create_issue "$title" "$body" "$initial_label")
        local issue_num
        issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$')
        new_issues+=("$issue_num")
      else
        echo "  Known advisory: $ghsa_id (issue #$existing_issue)"
        local current_updated_at
        current_updated_at=$(echo "$advisory" | jq -r '.updated_at')
        post_update_comment "$existing_issue" "$advisory"
      fi
    done < <(echo "$advisories" | jq -c '.[]')
  done <<< "$repos"

  # Output new issue numbers as JSON array for workflow matrix
  local issues_json
  if [ ${#new_issues[@]} -eq 0 ]; then
    issues_json="[]"
  else
    issues_json=$(printf '%s\n' "${new_issues[@]}" | jq -R . | jq -s .)
  fi
  echo "new-issues=$issues_json" >> "$output_file"
  echo "New issues: $issues_json"
}

# Allow sourcing for tests without running main
if [ "${1:-}" != "--source-only" ]; then
  main
fi
