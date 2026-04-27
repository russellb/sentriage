#!/usr/bin/env python3
"""Sync GitHub Security Advisories to issues in a sentriage instance repo.

Polls monitored repos for GHSAs and creates/updates corresponding issues.
Designed to run in a GitHub Actions workflow with a privileged PAT that has
security_events scope — no Claude or AI access needed.

Usage:
    sync-reports.py --config sentriage.yml [--initial-label needs-triage] [--dry-run]
    sync-reports.py --config sentriage.yml --ghsa-id GHSA-xxxx-xxxx-xxxx

Required environment variables:
    GITHUB_TOKEN      — PAT with repo scope.  Must be a real PAT, not the
                        default Actions GITHUB_TOKEN, so that issue-creation
                        events trigger downstream workflows.

Optional environment variables:
    GITHUB_OUTPUT — GitHub Actions output file (for setting workflow outputs)
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

GHSA_PATTERN = re.compile(r"GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}")

REQUIRED_LABELS = {
    "new-report": "#d93f0b",
    "needs-triage": "#e4e669",
    "triaged": "#0e8a16",
    "needs-review": "#1d76db",
    "accepted": "#0e8a16",
    "rejected-duplicate": "#cccccc",
    "rejected-invalid": "#cccccc",
    "rejected-out-of-scope": "#cccccc",
}


def gh(*args, check=True):
    """Run a gh CLI command and return stdout."""
    result = subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        if check:
            print(f"gh command failed: gh {' '.join(args)}", file=sys.stderr)
            if result.stderr:
                print(f"  stderr: {result.stderr.strip()}", file=sys.stderr)
            result.check_returncode()
        return ""
    return result.stdout.strip()


def gh_json(*args):
    """Run a gh CLI command and parse JSON output."""
    out = gh(*args, check=True)
    return json.loads(out) if out else None


def load_config(config_path):
    """Load and validate sentriage.yml."""
    try:
        import yaml
    except ImportError:
        print("Error: PyYAML is required. Install with: pip install pyyaml",
              file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(config_path):
        print(f"Error: config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path) as f:
        config = yaml.safe_load(f)

    repos = config.get("monitored_repos", [])
    if not repos:
        print("Warning: no monitored_repos configured", file=sys.stderr)
    for repo in repos:
        if "repo" not in repo:
            print(f"Error: monitored repo entry missing 'repo' field: {repo}",
                  file=sys.stderr)
            sys.exit(1)
    return config


def ensure_labels():
    """Create any missing sentriage labels in the instance repo."""
    existing_raw = gh("label", "list", "--json", "name", "--limit", "100")
    existing = {l["name"] for l in json.loads(existing_raw)} if existing_raw else set()

    for label, color in REQUIRED_LABELS.items():
        if label not in existing:
            print(f"  Creating label: {label}")
            gh("label", "create", label, "--color", color.lstrip("#"),
               "--description", f"Sentriage: {label}")


def fetch_advisories(repo, ghsa_id=None):
    """Fetch security advisories from a repo.

    When ghsa_id is given, searches all states (triage, draft, published)
    for that specific advisory.  Otherwise only fetches triage and draft
    advisories that still need attention.
    """
    states = ("triage", "draft", "published", "closed") if ghsa_id else ("triage", "draft")
    advisories = []
    for state in states:
        try:
            out = gh("api", f"repos/{repo}/security-advisories?state={state}",
                     "--header", "Accept: application/vnd.github+json",
                     "--paginate")
            batch = json.loads(out) if out else []
            if ghsa_id:
                batch = [a for a in batch if a.get("ghsa_id") == ghsa_id]
            advisories.extend(batch)
            if batch:
                print(f"  Found {len(batch)} {state} advisories")
        except subprocess.CalledProcessError:
            print(f"  Warning: could not fetch {state} advisories from {repo}",
                  file=sys.stderr)
    advisories.sort(key=lambda a: a.get("created_at", ""))
    return advisories


def find_existing_issues():
    """Build a map of GHSA ID -> issue number for all issues in this repo."""
    ghsa_map = {}
    try:
        out = gh("issue", "list", "--state", "all",
                 "--json", "number,title,body",
                 "--limit", "1000")
        issues = json.loads(out) if out else []
    except subprocess.CalledProcessError:
        return ghsa_map

    for issue in issues:
        match = GHSA_PATTERN.search(issue.get("title", ""))
        if match:
            ghsa_map[match.group(0)] = {
                "number": issue["number"],
                "body": issue.get("body", ""),
            }
    return ghsa_map


def format_issue_title(repo, summary, ghsa_id):
    return f"{repo}: {summary} ({ghsa_id})"


def format_issue_body(advisory, repo):
    ghsa_id = advisory["ghsa_id"]
    description = advisory.get("description", "No description provided.")
    severity = advisory.get("severity") or "unknown"
    cve_id = advisory.get("cve_id") or "N/A"
    published_at = advisory.get("published_at", "unknown")
    html_url = advisory.get("html_url", "")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    vulns = advisory.get("vulnerabilities", [])
    if vulns:
        affected = "\n".join(
            f"{v.get('package', {}).get('name', 'unknown')}: "
            f"{v.get('vulnerable_version_range', 'unspecified')}"
            for v in vulns
        )
    else:
        affected = "Not specified"

    return f"""## Vulnerability Report

| Field | Value |
|---|---|
| **Source Repo** | {repo} |
| **GHSA** | [{ghsa_id}]({html_url}) |
| **CVE** | {cve_id} |
| **Severity** | {severity} |
| **Published** | {published_at} |
| **Detected** | {now} |

### Affected Versions

{affected}

### Description

{description}"""


def format_update_comment(advisory):
    updated_at = advisory.get("updated_at", "unknown")
    description = advisory.get("description", "No description provided.")
    severity = advisory.get("severity") or "unknown"

    return f"""## Advisory Updated

This advisory was updated upstream at {updated_at}.

### Updated Description

{description}

### Updated Severity

{severity}"""


def advisory_changed(advisory, existing_body):
    """Check if the advisory content differs from the existing issue body."""
    new_severity = advisory.get("severity") or "unknown"
    new_description = advisory.get("description", "")

    return (
        new_severity not in existing_body
        or new_description not in existing_body
    )


def sync_repo(repo, initial_label, existing_issues, dry_run=False,
              ghsa_id_filter=None):
    """Sync advisories from one repo. Returns list of new issue numbers."""
    print(f"Checking {repo} for security advisories...")
    advisories = fetch_advisories(repo, ghsa_id=ghsa_id_filter)
    new_issues = []

    for advisory in advisories:
        ghsa_id = advisory.get("ghsa_id")
        summary = advisory.get("summary", "Untitled advisory")
        if not ghsa_id:
            continue

        existing = existing_issues.get(ghsa_id)

        if existing is None:
            # Draft advisories have already been triaged upstream
            state = advisory.get("state", "triage")
            label = "accepted" if state == "draft" else initial_label
            print(f"  New ({state}): {ghsa_id} — {summary}")
            if dry_run:
                print(f"    [dry-run] Would create issue with label '{label}'")
                continue

            title = format_issue_title(repo, summary, ghsa_id)
            body = format_issue_body(advisory, repo)
            issue_url = gh("issue", "create",
                           "--title", title,
                           "--body", body,
                           "--label", label)
            match = re.search(r"/(\d+)$", issue_url)
            if match:
                issue_num = int(match.group(1))
                new_issues.append(issue_num)
                existing_issues[ghsa_id] = {
                    "number": issue_num,
                    "body": body,
                }
                print(f"    Created issue #{issue_num}")
        else:
            issue_num = existing["number"]
            if advisory_changed(advisory, existing.get("body", "")):
                print(f"  Updated: {ghsa_id} (issue #{issue_num})")
                if dry_run:
                    print(f"    [dry-run] Would post update comment")
                    continue
                comment = format_update_comment(advisory)
                gh("issue", "comment", str(issue_num), "--body", comment)
                print(f"    Posted update comment on #{issue_num}")
            else:
                print(f"  Unchanged: {ghsa_id} (issue #{issue_num})")

    return new_issues


def set_github_output(key, value):
    """Write a key=value pair to GITHUB_OUTPUT."""
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a") as f:
            f.write(f"{key}={value}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Sync GitHub Security Advisories to sentriage issues",
    )
    parser.add_argument(
        "--config", default="sentriage.yml",
        help="Path to sentriage.yml config file (default: sentriage.yml)",
    )
    parser.add_argument(
        "--initial-label", default="needs-triage",
        choices=["needs-triage", "new-report"],
        help="Label to apply to new issues (default: needs-triage)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be done without making changes",
    )
    parser.add_argument(
        "--ghsa-id",
        help="Sync only this GHSA ID, regardless of its state",
    )
    args = parser.parse_args()

    if args.ghsa_id and not GHSA_PATTERN.fullmatch(args.ghsa_id):
        print(f"Error: invalid GHSA ID format: {args.ghsa_id}",
              file=sys.stderr)
        sys.exit(1)

    if not os.environ.get("GITHUB_TOKEN"):
        print("Error: GITHUB_TOKEN environment variable is required",
              file=sys.stderr)
        sys.exit(1)

    config = load_config(args.config)

    if not args.dry_run:
        print("--- Ensuring labels exist ---")
        ensure_labels()

    print("--- Loading existing issues ---")
    existing_issues = find_existing_issues()
    print(f"  Found {len(existing_issues)} existing tracked advisories")

    all_new_issues = []
    repos = config.get("monitored_repos", [])
    for repo_config in repos:
        repo = repo_config["repo"]
        new = sync_repo(repo, args.initial_label, existing_issues,
                        dry_run=args.dry_run, ghsa_id_filter=args.ghsa_id)
        all_new_issues.extend(new)

    issues_json = json.dumps(all_new_issues)
    set_github_output("new-issues", issues_json)

    print(f"\n--- Sync complete ---")
    print(f"  New issues created: {len(all_new_issues)}")
    if all_new_issues:
        print(f"  Issue numbers: {all_new_issues}")


if __name__ == "__main__":
    main()
