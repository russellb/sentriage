# Custom Skills

You can create custom triage skills to extend sentriage's analysis
capabilities.

## Writing a Skill

A skill is a markdown file that instructs the Claude agent on what
analysis to perform. Place your skill files anywhere in your instance
repo and reference them with the `skill-path` input.

### Structure

```markdown
# Skill: Your Skill Name

Describe what this skill does and what the agent should analyze.

## Your Task

Step-by-step instructions for the agent.

## Output Format

Define the JSON output structure.
```

### Required Output Fields

Every skill must instruct the agent to return at minimum:

```json
{
  "recommendation": "duplicate|invalid|valid|needs-more-info",
  "confidence": 0.0,
  "analysis": "Human-readable markdown analysis",
  "manipulation_detected": false,
  "manipulation_details": null
}
```

Additional fields specific to your skill can be added.

### Example: Check Public API Surface

```markdown
# Skill: Check Public API Surface

Determine whether this vulnerability affects the project's public API.

## Your Task

1. Read the vulnerability report
2. Identify the affected code paths
3. Trace whether these code paths are reachable from public API endpoints
4. If the vulnerability only affects internal/private code, note this
   as a mitigating factor

## Output Format

Return JSON with these fields:

- `recommendation`: "valid" if public API is affected, "needs-more-info"
  if uncertain
- `confidence`: your certainty level
- `analysis`: explanation with code references
- `public_endpoints_affected`: list of affected public endpoints
- `internal_only`: boolean, true if only internal code is affected
```

## Using Custom Skills in Workflows

```yaml
- uses: sentriage/sentriage/actions/run-skill@main
  with:
    github-token: ${{ secrets.SENTRIAGE_PAT }}
    issue-number: ${{ github.event.issue.number }}
    skill-path: skills/check-public-api.md
```

## Security Considerations

Custom skills run within the same security sandbox as built-in skills.
The base security instructions are always layered first and cannot be
overridden by skill prompts. Your custom skill should not instruct the
agent to:

- Execute code from cloned repositories
- Access other issues or reports
- Make network requests
- Modify files in cloned repositories
