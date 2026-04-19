#!/bin/bash
# Summarizes skill results and transitions issue labels.
#
# When sourced with --source-only, exports functions without running main.
# Required env vars (for main execution):
#   GITHUB_TOKEN  — PAT with repo scope
#   ISSUE_NUMBER  — issue number to finalize
set -euo pipefail

extract_sentriage_comments() {
  local comments_json="$1"
  echo "$comments_json" | jq -c '[.[] | select(.body | startswith("## Sentriage:"))]'
}

format_summary() {
  local comments_json="$1"

  local sentriage_comments
  sentriage_comments=$(extract_sentriage_comments "$comments_json")

  local summary="## Triage Summary

The following automated triage skills have been run on this report:

"

  while IFS= read -r comment; do
    local body
    body=$(echo "$comment" | jq -r '.body')

    local skill_name
    skill_name=$(echo "$body" | head -1 | sed 's/## Sentriage: //')

    local recommendation_line
    recommendation_line=$(echo "$body" | grep '^\*\*Recommendation:\*\*' || echo "No recommendation")

    summary+="### $skill_name
$recommendation_line

"
  done < <(echo "$sentriage_comments" | jq -c '.[]')

  echo "$summary
---
*This issue is now ready for human review. Please apply the appropriate disposition label (accepted, rejected-duplicate, rejected-invalid, or rejected-out-of-scope).*"
}

transition_labels() {
  local issue_number="$1"
  gh issue edit "$issue_number" --remove-label "needs-triage" 2>/dev/null || true
  gh issue edit "$issue_number" --add-label "triaged,needs-review"
}

main() {
  if [ -z "${ISSUE_NUMBER:-}" ]; then
    echo "Error: ISSUE_NUMBER is required" >&2
    exit 1
  fi

  echo "Finalizing triage for issue #$ISSUE_NUMBER"

  local comments
  comments=$(gh issue view "$ISSUE_NUMBER" --json comments --jq '.comments')

  local summary
  summary=$(format_summary "$comments")

  gh issue comment "$ISSUE_NUMBER" --body "$summary"

  transition_labels "$ISSUE_NUMBER"

  echo "Issue #$ISSUE_NUMBER finalized: triaged + needs-review"
}

# Allow sourcing for tests without running main
if [ "${1:-}" != "--source-only" ]; then
  main
fi
