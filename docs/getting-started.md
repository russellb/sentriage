# Getting Started

## Prerequisites

- A GitHub account with access to create private repositories
- A Personal Access Token (PAT) with `security_events` and `repo` scopes
- One or more repositories with GitHub Security Advisory reporting enabled
- Claude Code CLI credentials (Anthropic API key, Vertex AI, or Bedrock)

## Setup

### 1. Create your sentriage instance repo

Create a new **private** GitHub repository. This will be your sentriage
instance — where vulnerability reports are tracked and triaged.

### 2. Add secrets

In your instance repo, go to Settings > Secrets and variables > Actions,
and add:

- **`SENTRIAGE_PAT`** — Your PAT with `security_events` and `repo` scopes

Plus your Claude API credentials (one of):

- **`ANTHROPIC_API_KEY`** — For direct Anthropic API access
- **`GCP_SERVICE_ACCOUNT_KEY`** — Base64-encoded GCP service account key for Vertex AI
- AWS credentials for Bedrock

### 3. Create sentriage.yml

Create a `sentriage.yml` file in the root of your instance repo:

```yaml
monitored_repos:
  - repo: your-org/your-repo
    clone: true
    context_refs:
      - SECURITY.md
```

See [Configuration](configuration.md) for all options.

### 4. Add a workflow

Copy one of the reference workflows to `.github/workflows/` in your
instance repo:

- **[basic-triage.yml](../examples/workflows/basic-triage.yml)** —
  Fully automated: detect > triage > finalize on a schedule
- **[gated-triage.yml](../examples/workflows/gated-triage.yml)** —
  Detect on schedule, but wait for a human to apply `needs-triage`
  before running skills

### 5. Create labels

Create the following labels in your instance repo:

| Label | Color (suggested) |
|---|---|
| `new-report` | `#d93f0b` (red) |
| `needs-triage` | `#e4e669` (yellow) |
| `triaged` | `#0e8a16` (green) |
| `needs-review` | `#1d76db` (blue) |
| `accepted` | `#0e8a16` (green) |
| `rejected-duplicate` | `#cccccc` (gray) |
| `rejected-invalid` | `#cccccc` (gray) |
| `rejected-out-of-scope` | `#cccccc` (gray) |

### 6. (Optional) Add team instructions

Create a `CLAUDE.md` in your instance repo root with any team-specific
instructions for the agent:

```markdown
# Team Instructions

- Our project only considers vulnerabilities in the public API surface
  as HIGH or CRITICAL severity
- Memory safety issues in C extensions are always HIGH severity
- Denial of service attacks require authentication to be considered valid
```

### 7. (Optional) Add context documents

Create a `context/` directory with documents the agent should reference:

- `context/security-policy.md` — Your project's security policy
- `context/supported-versions.md` — Which versions receive security fixes
- `context/threat-model.md` — Your project's threat model

### 8. Wait for reports

The workflow will run on the configured schedule and create issues for
any new security advisories. You can also trigger it manually via
the "Run workflow" button in the Actions tab.
