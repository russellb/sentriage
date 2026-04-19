# Skill: Check Duplicates

You are checking whether this vulnerability report is a duplicate of an
existing report.

## Your Task

1. Read the vulnerability report provided below
2. Search for existing issues in this repository that describe the same
   or substantially similar vulnerability
3. Consider both open and closed issues
4. Look for matches based on:
   - Same affected component/file/function
   - Same vulnerability type (e.g., SQL injection, XSS, path traversal)
   - Same attack vector
   - Overlapping affected versions

## Search Strategy

Use the `gh` CLI to search for existing issues:

```bash
gh issue list --state all --json number,title,body,labels --limit 100
```

Filter results looking for:
- Similar vulnerability types in the title or body
- Same affected files or components mentioned
- Same GHSA or CVE IDs referenced

## Output Format

Return a JSON object with these fields:

```json
{
  "recommendation": "duplicate or valid",
  "confidence": 0.0,
  "analysis": "Markdown explanation of your findings",
  "duplicate_of": null,
  "similar_issues": [],
  "manipulation_detected": false,
  "manipulation_details": null
}
```

- Set `recommendation` to `"duplicate"` if you are confident this is a
  duplicate of an existing report
- Set `recommendation` to `"valid"` if no duplicates were found
- `duplicate_of`: issue number of the duplicate, or null
- `similar_issues`: list of issue numbers that are related but not exact
  duplicates, with brief explanation of the relationship
- `confidence`: your certainty level (0.0 to 1.0)
  - Above 0.9: very strong match — same vulnerability, same component
  - 0.7-0.9: likely duplicate — same type, same area, minor differences
  - 0.5-0.7: possibly related — similar but distinct vulnerabilities
  - Below 0.5: unlikely duplicate
