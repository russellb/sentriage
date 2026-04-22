#!/bin/bash
# Assembles the layered prompt, runs Claude via run-claude.sh, parses the
# result, posts it as an issue comment, and sets GitHub Actions outputs.
#
# Required env vars:
#   GITHUB_TOKEN       — token for the instance repo (issues, comments)
#   ISSUE_NUMBER       — issue number in the sentriage instance repo
#   SKILL              — name of a built-in skill (mutually exclusive with SKILL_PATH)
#   SKILL_PATH         — path to a custom skill file (mutually exclusive with SKILL)
#   SENTRIAGE_ROOT     — path to the sentriage repo root (for built-in skills/instructions)
#
# Optional env vars:
#   CONFIG_FILE        — path to sentriage.yml (default: sentriage.yml)
#   WORKSPACE_DIR      — directory for cloned repos (default: /tmp/sentriage-workspace)
#   TEAM_CLAUDE_MD     — path to team's CLAUDE.md (default: CLAUDE.md)
#   GITHUB_OUTPUT      — GitHub Actions output file
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-sentriage.yml}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/tmp/sentriage-workspace}"
TEAM_CLAUDE_MD="${TEAM_CLAUDE_MD:-CLAUDE.md}"

validate_inputs() {
  if [ -n "${SKILL:-}" ] && [ -n "${SKILL_PATH:-}" ]; then
    echo "Error: specify either 'skill' or 'skill_path', not both" >&2
    exit 1
  fi
  if [ -z "${SKILL:-}" ] && [ -z "${SKILL_PATH:-}" ]; then
    echo "Error: one of 'skill' or 'skill_path' must be specified" >&2
    exit 1
  fi
  if [ -z "${ISSUE_NUMBER:-}" ]; then
    echo "Error: ISSUE_NUMBER is required" >&2
    exit 1
  fi
  if [ -z "${SENTRIAGE_ROOT:-}" ]; then
    echo "Error: SENTRIAGE_ROOT is required" >&2
    exit 1
  fi
}

resolve_skill_path() {
  if [ -n "${SKILL:-}" ]; then
    local builtin_path="${SENTRIAGE_ROOT}/skills/${SKILL}.md"
    if [ ! -f "$builtin_path" ]; then
      echo "Error: built-in skill not found: $SKILL" >&2
      exit 1
    fi
    echo "$builtin_path"
  else
    if [ ! -f "$SKILL_PATH" ]; then
      echo "Error: custom skill not found: $SKILL_PATH" >&2
      exit 1
    fi
    echo "$SKILL_PATH"
  fi
}

fetch_report_content() {
  local issue_number="$1"
  gh issue view "$issue_number" --json body --jq '.body'
}

clone_configured_repos() {
  local config_file="$1" workspace="$2"
  mkdir -p "$workspace"

  if [ ! -f "$config_file" ]; then
    echo "Warning: config file not found, skipping repo cloning" >&2
    return
  fi

  local repos_json
  repos_json=$(python3 -c "
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
repos = [r for r in data.get('monitored_repos', []) if r.get('clone', False)]
print(json.dumps(repos))
" "$config_file")

  echo "$repos_json" | jq -c '.[]' | while IFS= read -r repo_config; do
    local repo_name
    repo_name=$(echo "$repo_config" | jq -r '.repo')
    local clone_dir="$workspace/$(echo "$repo_name" | tr '/' '_')"

    if [ -d "$clone_dir" ]; then
      echo "Updating $repo_name..."
      git -C "$clone_dir" pull --ff-only 2>/dev/null || true
    else
      echo "Cloning $repo_name..."
      git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${repo_name}.git" "$clone_dir" 2>/dev/null
    fi
  done
}

collect_context_refs() {
  local config_file="$1" workspace="$2"
  local context_dir="$workspace/context"
  rm -rf "$context_dir"
  mkdir -p "$context_dir"

  if [ ! -f "$config_file" ]; then
    return
  fi

  python3 -c "
import yaml, json, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for repo in data.get('monitored_repos', []):
    for ref in repo.get('context_refs', []):
        print(json.dumps({'repo': repo['repo'], 'ref': ref}))
" "$config_file" | while IFS= read -r entry; do
    local repo ref clone_dir src dst
    repo=$(echo "$entry" | jq -r '.repo')
    ref=$(echo "$entry" | jq -r '.ref')
    clone_dir="$workspace/$(echo "$repo" | tr '/' '_')"
    src="$clone_dir/$ref"
    dst="$context_dir/$(echo "$repo" | tr '/' '_')__$(echo "$ref" | tr '/' '_')"
    if [ -f "$src" ]; then
      cp "$src" "$dst"
      echo "  Context: $repo/$ref -> $dst"
    else
      echo "  Warning: context ref not found: $repo/$ref" >&2
    fi
  done
}

assemble_prompt() {
  local skill_file="$1" report_file="$2"
  local base_instructions="${SENTRIAGE_ROOT}/base-instructions.md"
  local prompt=""

  # Layer 1: Base instructions
  if [ -f "$base_instructions" ]; then
    prompt+="$(cat "$base_instructions")"
    prompt+=$'\n\n'
  fi

  # Layer 2: Team instructions
  if [ -f "$TEAM_CLAUDE_MD" ]; then
    prompt+="## Team Instructions"$'\n\n'
    prompt+="$(cat "$TEAM_CLAUDE_MD")"
    prompt+=$'\n\n'
  fi

  # Layer 3: Skill prompt
  prompt+="## Skill Instructions"$'\n\n'
  prompt+="$(cat "$skill_file")"
  prompt+=$'\n\n'

  # Layer 4: Context references (project security docs, etc.)
  local context_dir="$WORKSPACE_DIR/context"
  if [ -d "$context_dir" ] && [ "$(ls -A "$context_dir" 2>/dev/null)" ]; then
    prompt+="## Project Context"$'\n\n'
    prompt+="The following project documents are available for reference:"$'\n'
    for f in "$context_dir"/*; do
      prompt+="- $(basename "$f"): $f"$'\n'
    done
    prompt+="Read these files for context about the project's security policies and guidelines."$'\n\n'
  fi

  # Layer 5: Prepared context (from skill preparation script)
  local prepare_dir="$WORKSPACE_DIR/_prepare"
  if [ -d "$prepare_dir" ] && [ "$(ls -A "$prepare_dir" 2>/dev/null)" ]; then
    prompt+="## Prepared Context"$'\n\n'
    prompt+="Pre-gathered data for this skill is available in: $prepare_dir"$'\n\n'
  fi

  # Layer 6: Reference to report file (no user content in prompt)
  prompt+="## Vulnerability Report"$'\n\n'
  prompt+="The vulnerability report to analyze is in the file: $report_file"$'\n'
  prompt+="Read this file to begin your analysis."$'\n\n'

  # Layer 7: Output file path
  prompt+="## Output"$'\n\n'
  prompt+="Write your JSON result to: ${RESULT_FILE}"

  echo "$prompt"
}

post_comment() {
  local issue_number="$1" analysis="$2" skill_name="$3"
  local confidence="$4" recommendation="$5" draft_response="${6:-}"

  local comment="## Sentriage: ${skill_name}

${analysis}

---
**Recommendation:** ${recommendation} | **Confidence:** ${confidence}"

  if [ -n "$draft_response" ]; then
    comment+="

---
### Draft Response

${draft_response}"
  fi

  if [ "${SENTRIAGE_DRY_RUN:-}" = "1" ]; then
    echo ""
    echo "$comment"
  else
    gh issue comment "$issue_number" --body "$comment"
  fi
}

set_outputs() {
  local result_json="$1"
  local output_file="${GITHUB_OUTPUT:-/dev/null}"

  for field in recommendation confidence severity manipulation_detected; do
    local value
    value=$(jq -r ".$field // empty" "$result_json")
    if [ -n "$value" ]; then
      echo "$field=$value" >> "$output_file"
    fi
  done
}

main() {
  validate_inputs

  local skill_file
  skill_file=$(resolve_skill_path)
  local skill_name
  skill_name=$(basename "$skill_file" .md)

  echo "=== Running skill: $skill_name on issue #$ISSUE_NUMBER ==="

  # Fetch report content and write to file (never embedded in prompt)
  echo "--- Fetching report content ---"
  local report_file="$WORKSPACE_DIR/report.md"
  mkdir -p "$WORKSPACE_DIR"
  fetch_report_content "$ISSUE_NUMBER" > "$report_file"

  # Clone configured repos
  echo "--- Cloning configured repos ---"
  clone_configured_repos "$CONFIG_FILE" "$WORKSPACE_DIR"

  # Collect context reference files
  echo "--- Collecting context references ---"
  collect_context_refs "$CONFIG_FILE" "$WORKSPACE_DIR"

  # Run skill preparation script if one exists
  local prepare_script="${SENTRIAGE_ROOT}/scripts/prepare-${skill_name}.py"
  if [ -f "$prepare_script" ]; then
    local prepare_dir="$WORKSPACE_DIR/_prepare"
    echo "--- Running preparation script: prepare-${skill_name}.py ---"
    python3 "$prepare_script" --report "$report_file" --output-dir "$prepare_dir"
  fi

  # Set result file path — Claude writes its JSON result here
  local run_dir="$WORKSPACE_DIR/_run"
  mkdir -p "$run_dir"
  export RESULT_FILE="$run_dir/result.json"
  rm -f "$RESULT_FILE"

  # Assemble layered prompt (references report file, does not include its content)
  echo "--- Assembling prompt ---"
  local prompt
  prompt=$(assemble_prompt "$skill_file" "$report_file")

  # Write prompt to a file for run-claude.sh
  local prompt_file="$run_dir/prompt.md"
  echo "$prompt" > "$prompt_file"

  # Make workspace accessible to claude-ci user
  chmod -R a+rX "$WORKSPACE_DIR"
  touch "$RESULT_FILE" && chmod a+rw "$RESULT_FILE"
  touch "$run_dir/draft-assessment.json" && chmod a+rw "$run_dir/draft-assessment.json"

  # Run Claude via run-claude.sh (handles user switching, OTEL, FIFO streaming)
  echo "--- Running Claude ---"
  local scripts_dir="${SENTRIAGE_ROOT}/scripts"

  set +e
  bash "$scripts_dir/run-claude.sh" "$(cat "$prompt_file")" "$WORKSPACE_DIR"
  local rc=$?
  set -e

  rm -f "$prompt_file"

  if [ "$rc" -ne 0 ]; then
    echo "Error: Claude exited with code $rc" >&2
    exit $rc
  fi

  # Read structured result written by Claude
  echo "--- Reading result ---"
  if [ ! -s "$RESULT_FILE" ]; then
    echo "Error: Claude did not write result to $RESULT_FILE" >&2
    exit 1
  fi

  local recommendation confidence analysis draft_response
  recommendation=$(jq -r '.recommendation // "unknown"' "$RESULT_FILE")
  confidence=$(jq -r '.confidence // 0.0' "$RESULT_FILE")
  analysis=$(jq -r '.analysis // "No analysis available"' "$RESULT_FILE")
  draft_response=$(jq -r '.draft_response // empty' "$RESULT_FILE")

  # Post comment with results
  echo "--- Posting comment ---"
  post_comment "$ISSUE_NUMBER" "$analysis" "$skill_name" "$confidence" "$recommendation" "$draft_response"

  # Set action outputs for workflow branching
  set_outputs "$RESULT_FILE"

  echo "=== Skill $skill_name complete: recommendation=$recommendation confidence=$confidence ==="
}

main
