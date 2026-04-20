# Sentriage

<p align="center">
  <img src="docs/images/sentriage.png" alt="Sentriage logo" width="200">
</p>

<p align="center">
  AI-powered triage for private security vulnerability reports.<br>
  Automates severity assessment, deduplication, and validation.
</p>

## Overview

Sentriage is a set of composable tools that use AI to triage private
security vulnerability reports (GitHub Security Advisories). It helps
security teams process incoming reports faster by automating initial
analysis — either fully automatically or with human-in-the-loop
checkpoints at each stage.

### What it does

- **Syncs** new vulnerability reports from monitored repos into a private tracking repo
- **Checks for duplicates** against existing reports
- **Validates** whether reported vulnerabilities exist in the source code
- **Assesses severity** independently using CVSS criteria
- **Recommends** disposition with confidence scores
- **Short-circuits** the pipeline when a report is identified as duplicate or invalid
- **Never decides** — all final dispositions are made by humans

### Two operating modes

**Automated triage** — New reports are synced with a `needs-triage` label,
which immediately triggers AI analysis. Best for teams with high report
volume who want AI to do an initial pass before human review.

**Gated triage** — New reports are synced with a `new-report` label. A
human reviews the report and applies `needs-triage` when ready, triggering
AI analysis on demand. Best for teams who want to screen reports before
spending API credits.

Both modes produce the same output: skill results posted as issue comments
with confidence scores, ready for human review.

## How it works

Sentriage uses two separate workflows with distinct security boundaries:

```mermaid
graph LR
    A[Security Advisory<br>filed on monitored repo] -->|Sync workflow<br>privileged PAT| B[Issue created in<br>sentriage instance repo]
    B -->|Triage workflow<br>default GITHUB_TOKEN| C[AI skills analyze<br>the report]
    C --> D[Recommendations posted<br>as issue comments]
    D --> E[Human reviews<br>and decides]
```

### Detailed flow

```mermaid
flowchart TD
    subgraph source["Monitored Repo (e.g. vllm-project/vllm)"]
        A1[Reporter files<br>security advisory]
    end

    subgraph sync["Sync Workflow (cron)"]
        B1[Poll for new/updated<br>triage & draft advisories]
        B2[Create issue in<br>sentriage instance repo]
        B3[Post update comment<br>if advisory changed]
    end

    subgraph instance["Sentriage Instance Repo"]
        C1["Issue created with label:<br><b>new-report</b> (gated) or<br><b>needs-triage</b> (automated)"]
        C2[Human reviews &<br>applies needs-triage]
    end

    subgraph triage["Triage Workflow (event-driven)"]
        D1[check-duplicates]
        D2{Duplicate?}
        D3[check-validity]
        D4{Invalid?}
        D5[assess-severity]
        D6[finalize-triage]
    end

    subgraph review["Human Review"]
        E1[Review AI recommendations<br>& confidence scores]
        E2[Apply disposition label]
        E3["accepted"]
        E4["rejected-duplicate"]
        E5["rejected-invalid"]
        E6["rejected-out-of-scope"]
    end

    A1 --> B1
    B1 -->|New advisory| B2
    B1 -->|Updated advisory| B3
    B2 --> C1
    C1 -->|Gated mode| C2
    C1 -->|Automated mode| D1
    C2 -->|Label applied| D1
    D1 --> D2
    D2 -->|Yes| D6
    D2 -->|No| D3
    D3 --> D4
    D4 -->|Yes| D6
    D4 -->|No| D5
    D5 --> D6
    D6 -->|"Labels: triaged + needs-review"| E1
    E1 --> E2
    E2 --> E3
    E2 --> E4
    E2 --> E5
    E2 --> E6
```

### Security architecture

The sync and triage workflows are intentionally separated:

| Workflow | Token | Access | Runs |
|---|---|---|---|
| **Sync** | `ADVISORY_TOKEN` (privileged PAT) | Read advisories from monitored repos | No AI, just Python script |
| **Triage** | Default `GITHUB_TOKEN` | Read/write issues in instance repo only | Claude Code in container |

The privileged token never reaches the AI runtime. Report content is
written to a file on disk — it is never embedded in the AI prompt,
eliminating the primary prompt injection vector.

## Quick Start

See the [Getting Started](docs/getting-started.md) guide.

## Built-in Skills

| Skill | Purpose |
|---|---|
| `check-duplicates` | Find duplicate or related reports |
| `check-validity` | Validate vulnerability against source code |
| `assess-severity` | Independent CVSS severity assessment |

Each skill runs as an isolated Claude Code invocation in a fresh
container — no context is shared between reports or between skills.
You can also [write custom skills](docs/custom-skills.md).

## Documentation

- [Getting Started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [Custom Skills](docs/custom-skills.md)
- [Security Model](docs/security.md)

## Security

Sentriage is designed to handle sensitive security data. See the
[Security Model](docs/security.md) for details on how the system
protects against prompt injection, information leakage, and other threats.

If you discover a security vulnerability in sentriage itself, please
report it via GitHub's private vulnerability reporting feature.

## License

See [LICENSE](LICENSE).
