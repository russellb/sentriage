#!/bin/bash
# Run a sentriage skill locally against an issue.
#
# Usage:
#   run-local.sh <issue-number> [skill]
#   run-local.sh 1                          # runs full pipeline
#   run-local.sh 1 check-duplicates         # runs one skill
#   run-local.sh 1 validate-and-assess      # runs one skill
#
# Expects to be run from the instance repo directory (e.g., ~/src/vllm-sentriage).
# SENTRIAGE_ROOT defaults to ../sentriage (sibling directory).
#
# Set DRY_RUN=1 to skip posting comments and label changes.
set -euo pipefail

ISSUE_NUMBER="${1:?Usage: $0 <issue-number> [skill]}"
SKILL="${2:-}"

export SENTRIAGE_ROOT="${SENTRIAGE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}"
export ISSUE_NUMBER
export WORKSPACE_DIR="${WORKSPACE_DIR:-/tmp/sentriage-workspace}"
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-/tmp/sentriage-github-output}"
export SENTRIAGE_LOCAL=1

rm -f "$GITHUB_OUTPUT"
touch "$GITHUB_OUTPUT"

run_skill() {
  local skill="$1"
  echo ""
  echo "============================================"
  echo "  Running skill: $skill on issue #$ISSUE_NUMBER"
  echo "============================================"
  echo ""

  export SKILL="$skill"
  rm -f "$GITHUB_OUTPUT"
  touch "$GITHUB_OUTPUT"

  bash "$SENTRIAGE_ROOT/actions/run-skill/run.sh"

  echo ""
  echo "--- Outputs ---"
  cat "$GITHUB_OUTPUT"
  echo ""
}

read_output() {
  grep "^$1=" "$GITHUB_OUTPUT" 2>/dev/null | cut -d= -f2-
}

if [ -n "$SKILL" ]; then
  run_skill "$SKILL"
  exit 0
fi

# Full pipeline
echo "=== Running full triage pipeline on issue #$ISSUE_NUMBER ==="

run_skill "check-duplicates"
recommendation=$(read_output "recommendation")

if [ "$recommendation" = "duplicate" ]; then
  echo ">>> Short-circuiting: duplicate detected (skipping validate-and-assess)"
else
  run_skill "validate-and-assess"
fi

echo ""
echo "--- Skipping finalize (local mode) ---"

echo ""
echo "=== Triage complete for issue #$ISSUE_NUMBER ==="
