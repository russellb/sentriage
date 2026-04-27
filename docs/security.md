# Security Model

Sentriage processes potentially malicious content — vulnerability reports
could be crafted to manipulate the AI agent. This document describes the
security model and mitigations.

## Threat Model

### Prompt Injection

**Threat:** Report content attempts to override agent instructions.

**Mitigation (three layers):**

1. **File-based separation:** Report content is never included in the
   prompt. It is written to a file on disk, and the prompt tells Claude
   to read that file. This prevents user-controlled data from being
   interpreted as instructions.

2. **Instruction-level framing:** The base instructions explicitly tell
   the agent that report content is untrusted user input and must be
   treated as data, not instructions.

3. **Tool restriction:** Agents that read untrusted report content are
   restricted to a minimum set of tools (Read, Write, Glob, Grep). Even
   if prompt injection bypasses the instruction-level defenses, the agent
   cannot execute commands, make network requests, or access external
   services — limiting the blast radius of a successful injection to
   reading files and writing results.

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
