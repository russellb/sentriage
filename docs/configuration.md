# Configuration

## sentriage.yml

The `sentriage.yml` file in your instance repo root configures which
repositories sentriage monitors.

### Schema

```yaml
monitored_repos:
  - repo: owner/repo-name
    clone: true
    context_refs:
      - SECURITY.md
      - docs/security-policy.md
```

### Fields

#### `monitored_repos`

A list of repositories to monitor for security advisories.

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `repo` | string | yes | — | Repository in `owner/name` format |
| `clone` | boolean | no | `false` | Whether to clone this repo for source code analysis |
| `context_refs` | list | no | `[]` | Files in the repo to include as additional context |

### Notes

- The PAT must have `security_events` scope on all monitored repos
- Repos with `clone: true` will be cloned (shallow, read-only) when
  running skills that need source code access
- `context_refs` are files within the monitored repo that provide
  useful context (security policies, threat models, etc.)

## sync-reports.py

The sync script runs separately from Claude and handles polling monitored
repos for new/updated security advisories.

```
python3 scripts/sync-reports.py --config sentriage.yml [--initial-label needs-triage] [--dry-run]
```

| Argument | Default | Description |
|---|---|---|
| `--config` | `sentriage.yml` | Path to config file |
| `--initial-label` | `needs-triage` | Label for new issues (`needs-triage` or `new-report`) |
| `--dry-run` | — | Show what would be done without making changes |

Requires `GITHUB_TOKEN` env var with `security_events` and `repo` scope.

The sync script also creates any missing sentriage labels on first run.

## Action Inputs

### run-skill

| Input | Required | Default | Description |
|---|---|---|---|
| `github-token` | yes | — | PAT with `repo` scope |
| `issue-number` | yes | — | Issue number to analyze |
| `skill` | no* | — | Built-in skill name |
| `skill-path` | no* | — | Path to custom skill file |
| `config-file` | no | `sentriage.yml` | Path to config file |

*Exactly one of `skill` or `skill-path` must be provided.

### finalize-triage

| Input | Required | Default | Description |
|---|---|---|---|
| `github-token` | yes | — | PAT with `repo` scope |
| `issue-number` | yes | — | Issue number to finalize |

## AI Backend

Sentriage uses Claude Code and supports multiple AI backends. Configure
credentials via repository secrets and pass them as environment variables
in your workflow:

- **Anthropic API:** Set `ANTHROPIC_API_KEY`
- **Google Vertex AI:** Set `CLAUDE_CODE_USE_VERTEX=1`, `ANTHROPIC_VERTEX_PROJECT_ID`, and GCP credentials
- **Amazon Bedrock:** Set appropriate AWS credential environment variables

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_MODEL` | `claude-opus-4-6` | Claude model to use |
| `WORKSPACE_DIR` | `/tmp/sentriage-workspace` | Directory for cloned repos |

## Telemetry

Each skill run captures OpenTelemetry metrics (token usage and costs).
These are printed as a summary at the end of each run and saved as
`claude-otel.jsonl` for further analysis.
