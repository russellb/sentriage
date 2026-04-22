# Skill: Check Duplicates

You are checking whether this vulnerability report is a duplicate of an
existing report.

## Pre-gathered Data

A preparation script has already gathered data to assist you. Read the
files from the prepared context directory (referenced in the Prepared
Context section of your instructions) in this order:

### Step 1: Check for Exact Matches

Read `exact-matches.json`. If it contains any entries, those are
definitive duplicates — the same GHSA or CVE ID already appears in an
existing issue. Set your recommendation to "duplicate" with high
confidence and you are done.

### Step 2: Review the Report Metadata

Read `report-metadata.json` to understand the key characteristics of
the current report: GHSA/CVE IDs, affected files, vulnerability type
keywords, and severity.

### Step 3: Scan the Compact Index

Read `index.json`, which contains one entry per existing issue with:
- Issue number, title, GHSA/CVE IDs
- Affected files and vulnerability keywords
- A short description summary
- Current labels and state

Scan this index for potential duplicates by looking for overlap in:
- Same affected component or file paths
- Same vulnerability type (e.g., both are path traversal)
- Same source repository and similar description

### Step 4: Deep-read Candidates Only

If you identified candidate matches from the index, read their full
issue bodies from `issues/<number>.md` to confirm whether they
describe the same vulnerability. Only read the specific candidates —
do not read all issue files.

If no candidates looked similar in the index, skip this step.

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
