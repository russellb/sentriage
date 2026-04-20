#!/bin/bash
# Assembles the layered prompt, runs Claude via run-claude.sh, parses the
# result, posts it as an issue comment, and sets GitHub Actions outputs.
#
# Required env vars:
#   GITHUB_TOKEN       — PAT with repo scope
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

    if [ ! -d "$clone_dir" ]; then
      echo "Cloning $repo_name (read-only)..."
      git clone --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${repo_name}.git" "$clone_dir" 2>/dev/null
      chmod -R a-w "$clone_dir"
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

  # Layer 4: Reference to report file (no user content in prompt)
  prompt+="## Vulnerability Report"$'\n\n'
  prompt+="The vulnerability report to analyze is in the file: $report_file"$'\n'
  prompt+="Read this file to begin your analysis."

  echo "$prompt"
}

post_comment() {
  local issue_number="$1" analysis="$2" skill_name="$3"
  local confidence="$4" recommendation="$5"

  local comment="## Sentriage: ${skill_name}

${analysis}

---
**Recommendation:** ${recommendation} | **Confidence:** ${confidence}"

  gh issue comment "$issue_number" --body "$comment"
}

set_outputs() {
  local result_dir="$1"
  local output_file="${GITHUB_OUTPUT:-/dev/null}"

  for field in recommendation confidence severity manipulation_detected; do
    if [ -f "$result_dir/$field" ]; then
      echo "$field=$(cat "$result_dir/$field")" >> "$output_file"
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

  # Assemble layered prompt (references report file, does not include its content)
  echo "--- Assembling prompt ---"
  local prompt
  prompt=$(assemble_prompt "$skill_file" "$report_file")

  # Write prompt to a temp file (avoid shell argument length limits)
  local prompt_file
  prompt_file=$(mktemp)
  echo "$prompt" > "$prompt_file"

  # Capture raw stream output for result extraction
  local stream_capture="/tmp/sentriage-stream-capture.jsonl"
  rm -f "$stream_capture"

  # Run Claude via run-claude.sh
  echo "--- Running Claude ---"
  local scripts_dir="${SENTRIAGE_ROOT}/scripts"

  # Tee the FIFO output so both stream-claude.py (live display) and
  # extract-result.py (post-run parsing) can read it.
  # We modify run-claude.sh's approach: run claude directly here with
  # the same flags, capturing output for both live display and extraction.
  local claude_fifo="/tmp/claude-stream.fifo"
  rm -f "$claude_fifo"
  mkfifo "$claude_fifo"

  # Start OTEL collector
  export OTEL_LOG_FILE="/tmp/claude-otel.jsonl"
  rm -f "$OTEL_LOG_FILE"
  python3 "$scripts_dir/otel-collector.py" &
  local otel_pid=$!

  export CLAUDE_CODE_ENABLE_TELEMETRY=1
  export OTEL_METRICS_EXPORTER=otlp
  export OTEL_LOGS_EXPORTER=otlp
  export OTEL_EXPORTER_OTLP_PROTOCOL=http/json
  export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
  export OTEL_METRIC_EXPORT_INTERVAL=10000
  export PATH="$HOME/.local/bin:$PATH"

  set +e
  claude -p "$(cat "$prompt_file")" \
    --model "${CLAUDE_MODEL:-claude-opus-4-6}" \
    --dangerously-skip-permissions \
    --output-format stream-json \
    --include-partial-messages \
    --verbose 2>/tmp/claude-stderr.log | tee "$stream_capture" > "$claude_fifo" &
  local claude_pid=$!

  python3 -u "$scripts_dir/stream-claude.py" --claude-pid "$claude_pid" < "$claude_fifo"
  local stream_rc=$?

  kill "$claude_pid" 2>/dev/null
  wait "$claude_pid" 2>/dev/null
  local rc=$?

  if [ "$stream_rc" -eq 0 ] && [ "$rc" -ne 0 ]; then
    rc=0
  fi

  rm -f "$claude_fifo" "$prompt_file"

  sleep 7
  kill $otel_pid 2>/dev/null
  wait $otel_pid 2>/dev/null

  echo ""
  echo "--- OTEL Token/Cost Summary ---"
  python3 "$scripts_dir/otel-summary.py" "$OTEL_LOG_FILE"
  set -e

  if [ "$rc" -ne 0 ]; then
    echo "Error: Claude exited with code $rc" >&2
    exit $rc
  fi

  # Extract structured result
  echo "--- Extracting result ---"
  local result_dir="/tmp/sentriage-result"
  rm -rf "$result_dir"
  python3 "$scripts_dir/extract-result.py" "$stream_capture" "$result_dir"

  # Read result fields
  local recommendation confidence analysis
  recommendation=$(cat "$result_dir/recommendation" 2>/dev/null || echo "unknown")
  confidence=$(cat "$result_dir/confidence" 2>/dev/null || echo "0.0")
  analysis=$(cat "$result_dir/analysis" 2>/dev/null || echo "No analysis available")

  # Post comment with results
  echo "--- Posting comment ---"
  post_comment "$ISSUE_NUMBER" "$analysis" "$skill_name" "$confidence" "$recommendation"

  # Set action outputs for workflow branching
  set_outputs "$result_dir"

  echo "=== Skill $skill_name complete: recommendation=$recommendation confidence=$confidence ==="
}

main
