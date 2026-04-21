# Skill: Validate and Assess Severity

You are validating whether this vulnerability report describes a real,
exploitable vulnerability, and performing an independent severity
assessment.

## Your Task

### Part 1: Validate the Report

1. Read the vulnerability report
2. Examine the source code in your workspace to validate the claims
3. Check whether:
   - The affected code path exists
   - The described vulnerability type matches the actual code behavior
   - The attack vector is feasible (inputs reach the vulnerable code)
   - The claimed impact is realistic
4. Do NOT execute, build, or test the code — only read and analyze it
5. Look for existing mitigations (input validation, sanitization,
   access controls) that the reporter may not have accounted for
6. Consider the deployment context described in the project's security
   policy (if available in the project context files)

### Part 2: Assess Severity

If the vulnerability appears valid, assess severity using CVSS v3.1
base metrics:
- Attack Vector (Network/Adjacent/Local/Physical)
- Attack Complexity (Low/High)
- Privileges Required (None/Low/High)
- User Interaction (None/Required)
- Scope (Unchanged/Changed)
- Confidentiality Impact (None/Low/High)
- Integrity Impact (None/Low/High)
- Availability Impact (None/Low/High)

Compare your assessment with the reporter's claimed severity.

## Analysis Approach

- Start by identifying the specific files, functions, or endpoints
  mentioned in the report
- Trace the data flow from user input to the potentially vulnerable code
- Look for existing mitigations that the reporter may not have accounted for
- Use the project's security policy and guidelines to inform your
  severity assessment

## Output Format

Return a JSON object with these fields:

```json
{
  "recommendation": "valid or invalid or needs-more-info",
  "confidence": 0.0,
  "analysis": "Markdown explanation covering both validity and severity",
  "affected_files": [],
  "attack_vector_feasible": true,
  "existing_mitigations": [],
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

- Set `recommendation` to `"valid"` if the vulnerability appears real
- Set `recommendation` to `"invalid"` if the code does not behave as
  described, mitigations exist, or the attack vector is not feasible
- Set `recommendation` to `"needs-more-info"` if you cannot determine
  validity with the available information
- `affected_files`: list of file paths that contain the vulnerable code
- `attack_vector_feasible`: whether the described attack can reach the
  vulnerable code
- `existing_mitigations`: any existing protections you found
- `severity`: your independent assessment (critical/high/medium/low/none)
- `cvss_score`: calculated CVSS v3.1 base score (0.0 to 10.0)
- `cvss_vector`: full CVSS vector string
- `cvss_breakdown`: individual metric values
- `reporter_severity`: what the reporter claimed
- `severity_agrees`: whether your assessment matches the reporter's
- `severity_rationale`: explanation of why you agree or disagree
- If the report is invalid, you may omit the CVSS fields
