# Skill: Assess Severity

You are performing an independent severity assessment of this vulnerability
report using CVSS (Common Vulnerability Scoring System) criteria.

## Your Task

1. Read the vulnerability report provided below
2. Examine the source code in your workspace if available
3. Review any project security policy in the context/ directory
4. Assess severity independently using CVSS v3.1 base metrics:
   - Attack Vector (Network/Adjacent/Local/Physical)
   - Attack Complexity (Low/High)
   - Privileges Required (None/Low/High)
   - User Interaction (None/Required)
   - Scope (Unchanged/Changed)
   - Confidentiality Impact (None/Low/High)
   - Integrity Impact (None/Low/High)
   - Availability Impact (None/Low/High)
5. Compare your assessment with the reporter's claimed severity

## Output Format

Return a JSON object with these fields:

```json
{
  "recommendation": "valid",
  "confidence": 0.0,
  "analysis": "Markdown explanation of severity assessment",
  "severity": "critical|high|medium|low|none",
  "cvss_score": 0.0,
  "cvss_vector": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
  "cvss_breakdown": {
    "attack_vector": "Network",
    "attack_complexity": "Low",
    "privileges_required": "None",
    "user_interaction": "None",
    "scope": "Unchanged",
    "confidentiality": "High",
    "integrity": "High",
    "availability": "High"
  },
  "reporter_severity": "high",
  "severity_agrees": true,
  "severity_rationale": "Explanation of agreement or disagreement",
  "manipulation_detected": false,
  "manipulation_details": null
}
```

- `severity`: your independent assessment (critical/high/medium/low/none)
- `cvss_score`: calculated CVSS v3.1 base score (0.0 to 10.0)
- `cvss_vector`: full CVSS vector string
- `cvss_breakdown`: individual metric values
- `reporter_severity`: what the reporter claimed
- `severity_agrees`: whether your assessment matches the reporter's
- `severity_rationale`: explanation of why you agree or disagree
