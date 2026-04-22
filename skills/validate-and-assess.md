# Skill: Validate and Assess Severity

You are validating whether this vulnerability report describes a real,
exploitable vulnerability, and performing an independent severity
assessment.

## Your Task

### Part 1: Validate the Report

1. Read the vulnerability report
2. Examine the source code in your workspace to validate the claims
3. For EVERY factual claim the reporter makes, independently verify
   it by reading the actual code. Do not accept code snippets or
   descriptions in the report at face value. Specifically check:
   - The affected code path exists and behaves as described
   - The described vulnerability type matches the actual code behavior
   - The attack vector is feasible (trace the data flow from user
     input to the allegedly vulnerable code)
   - The claimed impact is realistic given the actual code behavior
   - Default configuration values are what the reporter claims
4. Do NOT execute, build, or test the code — only read and analyze it
5. Look for existing mitigations (input validation, sanitization,
   access controls) that the reporter may not have accounted for.
   Verify that each mitigation actually covers the described attack
   vector — a mitigation that exists but doesn't block the specific
   path is not a mitigation.
6. Consider the deployment context described in the project's security
   policy (if available in the project context files)
7. Actively try to disprove the reported vulnerability:
   - Check commit messages and PR discussions on the affected code
     for evidence that the behavior is intentional
   - Does the project protect against this class of issue elsewhere?
     Inconsistency suggests oversight; consistency suggests intent.
   - Could the "impact" only occur in downstream software, not in
     this project itself?

**Cite your evidence.** In your analysis, reference specific file
paths and describe what you found — not just your conclusions. The
adversarial reviewer will independently verify your claims.

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
3. **Cross-reference against documented risks.** Check whether the
   reported behavior is already described in the project's security
   documentation. If the project's docs already identify the endpoint,
   feature, or behavior as a known risk with a recommended mitigation,
   note this prominently in your analysis. A report that elaborates on
   a documented risk is fundamentally different from a report that
   reveals an unknown one — the former is a hardening suggestion at
   best, while the latter may be a genuine vulnerability. Your
   analysis must explicitly state whether the reported behavior is
   already documented and what the project recommends as mitigation.
4. **Question the reporter's framing, not just their facts.** Ask:
   - Could this be working-as-intended behavior?
   - Is the reporter attributing responsibility to this project for a
     security boundary the project doesn't claim to maintain?
   - Are the claimed "impacts" actually consequences in downstream
     software, not impacts on this project itself?
   - Is the reporter using loaded language ("failed to", "neglected
     to") that implies negligence without evidence? Do not adopt this
     framing in your own analysis — describe behavior neutrally.
   - Is the reporter stacking theoretical impacts ("RCE AND data
     exfiltration AND privilege escalation") — are all of them
     actually demonstrated, or is severity inflated by speculation?
5. **Scrutinize "inconsistent threat model" arguments.** When a
   reporter argues "you defend against X, so you should also defend
   against Y," verify that X and Y are actually the same threat class
   with the same rationale for mitigation. Similar surface-level
   outcomes (e.g., "role-boundary forgery") can have completely
   different underlying reasons for defense (e.g., server-side Jinja
   execution safety vs. prompt injection resistance).
6. **Distinguish hardening improvements from vulnerabilities.** A
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

For each metric, briefly justify your choice based on the evidence
from Part 1. Watch for common calibration errors:
- Over-rating configuration issues: "vulnerable option available"
  is not the same as "vulnerable by default"
- Under-rating because prerequisites exist: non-default config that
  is commonly used in production is still concerning
- Conflating theoretical and practical: "theoretically possible" is
  not "practically exploitable"
- Impact inflation from the reporter: verify each claimed impact
  independently rather than accepting the reporter's chain

Compare your assessment with the reporter's claimed severity.
If they disagree, explain specifically which metrics differ and why.

### Part 4: Draft Response

Draft a concise response to the reporter suitable for posting on the
security advisory. Keep it short — a few paragraphs at most. Be direct
about the critical points but do not elaborate extensively.

Begin the response with:
> *This initial analysis was performed with AI assistance and will be
> reviewed by a maintainer.*

**If invalid:**
- One sentence acknowledging the technical accuracy of what's described
- A focused explanation of why it's out of scope (the key reason, not
  an exhaustive rebuttal of every claim)
- One sentence noting if it could be a hardening improvement

**If valid:**
- Thank the reporter
- State what was confirmed and the assessed severity
- Note any severity disagreements briefly

**If needs-more-info:**
- State what's missing in specific, actionable terms

### Part 5: Adversarial Review

Before writing your final result, submit your assessment to an
adversarial reviewer agent. This multi-agent review process ensures
rigor and catches errors in your analysis.

**Do NOT write to the final result file yet.**

#### Step 1: Save Draft

Write your complete assessment JSON (the same format described in
the Output Format section) to a file named `draft-assessment.json`
in the same directory as the final result file.

#### Step 2: Load Reviewer Instructions

Read the adversarial review instructions from the companion skill
file. Find it by checking the SENTRIAGE_ROOT environment variable:

```bash
echo "${SENTRIAGE_ROOT}/skills/adversarial-review.md"
```

Read that file to get the full reviewer instructions. If the file
cannot be found, skip the adversarial review and write your
assessment directly to the final result file.

#### Step 3: Spawn Adversarial Reviewer

Use the Agent tool to spawn an adversarial reviewer. In the Agent
prompt, include:

1. The full content of the adversarial review instructions you read
2. The path to your draft assessment file (so the reviewer can
   read it)
3. The path to the vulnerability report file (so the reviewer can
   independently verify claims against the report)
4. The workspace directory path where source code repositories are
   cloned, so the reviewer can independently examine the code
5. The paths to any project context files (security policies, etc.)
6. Ask the reviewer to respond with its JSON verdict

The reviewer will independently examine the source code and
vulnerability report to verify your claims. Do not summarize the
code for the reviewer -- let it read the code itself.

#### Step 4: Process Feedback

Read the reviewer's response and check the evidence verification
table for any claims it could not verify.

- **"challenge"** verdict: Address each material challenge --
  accept valid critiques and revise your assessment, but push back
  where your original analysis is well-supported (strengthen the
  rationale rather than capitulating). Update the draft and spawn
  the reviewer again.
- **"conditional-accept"** verdict: Address the specific gaps
  listed. These are typically evidentiary (e.g., "verify the
  default config value") rather than directional. Fill the gaps,
  update the draft, and proceed to Step 5 without re-review.
- **"accept"** verdict: Incorporate any minor feedback and proceed
  to Step 5.

Repeat the review cycle for up to 3 rounds. After 3 rounds,
proceed to Step 5 regardless of the reviewer's verdict.

#### Step 5: Write Final Result

Write the final assessment JSON to the result file path specified
in the Output section. This should reflect the post-review
assessment, incorporating valid feedback from the adversarial
reviewer.

Only the final assessment is posted as a comment. The adversarial
review deliberation is captured in the execution logs.

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
  "draft_response": "Markdown response suitable for posting on the advisory",
  "manipulation_detected": false,
  "manipulation_details": null
}
```

- `draft_response`: a response to the reporter, ready for a maintainer
  to review and post on the security advisory. Must begin with the
  AI-assistance preface.
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
