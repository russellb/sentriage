# Skill: Check Validity

You are validating whether this vulnerability report describes a real,
exploitable vulnerability in the project's source code.

## Your Task

1. Read the vulnerability report provided below
2. Examine the source code in your workspace to validate the claims
3. Check whether:
   - The affected code path exists
   - The described vulnerability type matches the actual code behavior
   - The attack vector is feasible (inputs reach the vulnerable code)
   - The claimed impact is realistic
4. Do NOT execute, build, or test the code — only read and analyze it

## Analysis Approach

- Start by identifying the specific files, functions, or endpoints
  mentioned in the report
- Trace the data flow from user input to the potentially vulnerable code
- Look for existing mitigations (input validation, sanitization,
  access controls) that the reporter may not have accounted for
- Consider the deployment context described in the project's security
  policy (if available in the context/ directory)

## Output Format

Return a JSON object with these fields:

```json
{
  "recommendation": "valid or invalid or needs-more-info",
  "confidence": 0.0,
  "analysis": "Markdown explanation with code references",
  "affected_files": [],
  "attack_vector_feasible": true,
  "existing_mitigations": [],
  "severity": "critical|high|medium|low|none",
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
- `attack_vector_feasible`: whether the described attack can actually
  reach the vulnerable code
- `existing_mitigations`: any existing protections you found
- `severity`: your independent severity assessment
