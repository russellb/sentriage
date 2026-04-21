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

### Part 2: Assess Scope

Before assessing severity, determine whether the reported behavior
falls within the project's security scope. A report can be technically
accurate about code behavior while being wrong about whether that
behavior constitutes a vulnerability in this project.

1. **Identify the security boundary being claimed.** What security
   property does the reporter claim the project should maintain?
   (e.g., "role-separation integrity", "input sanitization",
   "authentication enforcement")
2. **Verify the project actually claims this boundary.** Check the
   project's security documentation, security policy, and existing
   security advisories. Does the project treat this as a security
   property it maintains? Or is responsibility delegated to deployers,
   client applications, or other layers of the stack?
3. **Question the reporter's framing, not just their facts.** Ask:
   - Could this be working-as-intended behavior?
   - Is the reporter attributing responsibility to this project for a
     security boundary the project doesn't claim to maintain?
   - Are the claimed "impacts" actually consequences in downstream
     software, not impacts on this project itself?
4. **Scrutinize "inconsistent threat model" arguments.** When a
   reporter argues "you defend against X, so you should also defend
   against Y," verify that X and Y are actually the same threat class
   with the same rationale for mitigation. Similar surface-level
   outcomes (e.g., "role-boundary forgery") can have completely
   different underlying reasons for defense (e.g., server-side Jinja
   execution safety vs. prompt injection resistance).
5. **Distinguish hardening improvements from vulnerabilities.** A
   change that would make software more robust is not the same as a
   security vulnerability. If the behavior is better described as a
   feature request or defense-in-depth improvement, say so — set
   recommendation to "invalid" with a clear explanation that the
   behavior is real but out of scope, and note it may be worth
   considering as a hardening improvement.

If the behavior is out of scope for the project's security model,
set recommendation to "invalid" and skip Part 3. Explain why the
behavior — while technically real — does not constitute a
vulnerability in this project.

### Part 3: Assess Severity

If the vulnerability appears valid AND in scope, assess severity
using CVSS v3.1 base metrics:
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
  "in_scope": true,
  "scope_rationale": "Why this is or is not within the project's security scope",
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

- Set `recommendation` to `"valid"` if the vulnerability is real AND
  within the project's security scope
- Set `recommendation` to `"invalid"` if the code does not behave as
  described, mitigations exist, the attack vector is not feasible,
  OR the behavior is out of scope for the project's security model
  (even if technically real)
- Set `recommendation` to `"needs-more-info"` if you cannot determine
  validity with the available information
- `affected_files`: list of file paths that contain the vulnerable code
- `attack_vector_feasible`: whether the described attack can reach the
  vulnerable code
- `existing_mitigations`: any existing protections you found
- `in_scope`: whether the behavior falls within the project's security
  scope (false if it's a feature request, hardening suggestion, or
  responsibility of a different layer)
- `scope_rationale`: explanation of why this is or is not in scope
- `severity`: your independent assessment (critical/high/medium/low/none)
- `cvss_score`: calculated CVSS v3.1 base score (0.0 to 10.0)
- `cvss_vector`: full CVSS vector string
- `cvss_breakdown`: individual metric values
- `reporter_severity`: what the reporter claimed
- `severity_agrees`: whether your assessment matches the reporter's
- `severity_rationale`: explanation of why you agree or disagree
- If the report is invalid, you may omit the CVSS fields
