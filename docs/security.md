# Security Model

Sentriage processes potentially malicious content — vulnerability reports
could be crafted to manipulate the AI agent. This document describes the
security model and mitigations.

## Threat Model

### Prompt Injection

**Threat:** Report content attempts to override agent instructions.

**Mitigation:** Report content is wrapped in `<vulnerability-report>` tags.
The base instructions explicitly tell the agent to treat content within
these tags as untrusted user input, never as instructions.

### Information Leakage

**Threat:** Attempts to extract information about other reports, the
sentriage repo, or the team's security posture.

**Mitigation:** Each skill invocation runs as an isolated subagent in a
fresh container. The agent only sees the single report being evaluated
and the configured source repositories. It has no access to other issues.

### Code Execution

**Threat:** Malicious payloads embedded in report content.

**Mitigation:** The containerized runtime blocks code execution. Cloned
repositories are mounted read-only. The agent is never instructed to run,
build, or test code.

### Social Engineering

**Threat:** Subtle manipulation to bias the agent's recommendation.

**Mitigation:** Confidence scores make the agent's certainty transparent.
The agent never makes final decisions — humans review all recommendations.
The base instructions tell the agent to flag manipulation attempts.

## Access Boundaries

| Resource | Read | Write |
|---|---|---|
| Vulnerability report | Single report only | No |
| Source repos | Configured repos, read-only | No |
| Instance repo issues | Current issue only | Comments only |
| Other issues | No | No |
| Team context docs | Yes | No |
| Network | AI API endpoint only | No |

## PAT Scoping

Use a fine-grained PAT scoped to only the required repositories:

- **Instance repo:** Read/write issues and comments
- **Monitored repos:** Read security advisories, read/clone repository

Avoid using classic PATs with broad `repo` scope if possible.

## Responsible Disclosure

If you discover a security vulnerability in sentriage itself, please
report it via GitHub's private vulnerability reporting feature on the
sentriage repository.
