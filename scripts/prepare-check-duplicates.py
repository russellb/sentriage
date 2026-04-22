#!/usr/bin/env python3
"""Pre-gather duplicate detection context for the check-duplicates skill.

Extracts metadata from the current report and builds a compact index of
existing issues so the agent can identify duplicates without running
many search queries.

Usage:
    prepare-check-duplicates.py --report <path> --output-dir <path>

Required environment variables:
    GITHUB_TOKEN    — Token for the instance repo
    ISSUE_NUMBER    — Current issue number (excluded from candidate list)
"""

import argparse
import json
import os
import re
import subprocess
import sys

GHSA_PATTERN = re.compile(r"GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}")
CVE_PATTERN = re.compile(r"CVE-\d{4}-\d+")
# Match file paths like vllm/plugins/foo.py — at least one directory separator
FILE_PATH_PATTERN = re.compile(
    r"(?:^|[\s`\(])([a-zA-Z_][a-zA-Z0-9_./\-]*"
    r"/[a-zA-Z0-9_./\-]*\.[a-z]{1,4})(?:[\s`\),:;]|$)",
    re.MULTILINE,
)

VULN_KEYWORDS = [
    "path traversal", "directory traversal",
    "remote code execution", "rce",
    "sql injection", "sqli",
    "cross-site scripting", "xss",
    "server-side request forgery", "ssrf",
    "denial of service", "dos", "resource exhaustion",
    "authentication bypass", "auth bypass",
    "privilege escalation",
    "information disclosure", "data leak",
    "command injection", "code injection",
    "deserialization", "template injection",
    "buffer overflow", "memory corruption",
    "race condition", "toctou",
]


def extract_report_metadata(report_path):
    """Extract structured metadata from the vulnerability report."""
    with open(report_path) as f:
        content = f.read()

    content_lower = content.lower()

    ghsa_ids = list(set(GHSA_PATTERN.findall(content)))
    cve_ids = list(set(CVE_PATTERN.findall(content)))
    file_paths = list(set(FILE_PATH_PATTERN.findall(content)))
    # Filter out things that look like URLs or version strings
    file_paths = [
        p for p in file_paths
        if not p.startswith("http") and not p.startswith("www.")
    ]

    keywords = [kw for kw in VULN_KEYWORDS if kw in content_lower]

    # Extract severity from the structured table
    severity_match = re.search(r"\*\*Severity\*\*\s*\|\s*(\w+)", content)
    severity = severity_match.group(1).lower() if severity_match else None

    # Extract source repo
    repo_match = re.search(r"\*\*Source Repo\*\*\s*\|\s*(\S+)", content)
    source_repo = repo_match.group(1) if repo_match else None

    return {
        "ghsa_ids": ghsa_ids,
        "cve_ids": cve_ids,
        "file_paths": file_paths,
        "vulnerability_keywords": keywords,
        "severity": severity,
        "source_repo": source_repo,
    }


def fetch_existing_issues():
    """Fetch all issues from the instance repo."""
    result = subprocess.run(
        [
            "gh", "issue", "list", "--state", "all",
            "--json", "number,title,body,labels,state,createdAt",
            "--limit", "1000",
        ],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout) if result.stdout.strip() else []


def build_index_entry(issue):
    """Build a compact index entry for one issue."""
    title = issue.get("title", "")
    body = issue.get("body", "")
    body_lower = body.lower()

    ghsa_match = GHSA_PATTERN.search(title) or GHSA_PATTERN.search(body)
    cve_match = CVE_PATTERN.search(body)

    severity_match = re.search(r"\*\*Severity\*\*\s*\|\s*(\w+)", body)
    repo_match = re.search(r"\*\*Source Repo\*\*\s*\|\s*(\S+)", body)

    file_paths = list(set(FILE_PATH_PATTERN.findall(body)))
    file_paths = [
        p for p in file_paths
        if not p.startswith("http") and not p.startswith("www.")
    ]

    keywords = [kw for kw in VULN_KEYWORDS if kw in body_lower]

    # First ~300 chars of the description for quick scanning
    desc_match = re.search(r"### Description\s*\n(.*?)(?=\n###|\Z)", body, re.DOTALL)
    summary = desc_match.group(1).strip()[:300] if desc_match else ""

    labels = [la.get("name", "") for la in issue.get("labels", [])]

    return {
        "number": issue["number"],
        "title": title,
        "ghsa_id": ghsa_match.group(0) if ghsa_match else None,
        "cve_id": cve_match.group(0) if cve_match else None,
        "severity": severity_match.group(1).lower() if severity_match else None,
        "source_repo": repo_match.group(1) if repo_match else None,
        "affected_files": file_paths[:10],
        "vulnerability_keywords": keywords,
        "summary": summary,
        "labels": labels,
        "state": issue.get("state", ""),
        "created_at": issue.get("createdAt", ""),
    }


def find_exact_matches(report_meta, index):
    """Find definitive duplicates by GHSA/CVE ID match."""
    matches = []
    for entry in index:
        for ghsa in report_meta["ghsa_ids"]:
            if entry["ghsa_id"] == ghsa:
                matches.append({
                    "issue_number": entry["number"],
                    "match_type": "ghsa_id",
                    "match_value": ghsa,
                    "title": entry["title"],
                })
        for cve in report_meta["cve_ids"]:
            if entry["cve_id"] == cve:
                matches.append({
                    "issue_number": entry["number"],
                    "match_type": "cve_id",
                    "match_value": cve,
                    "title": entry["title"],
                })
    return matches


def main():
    parser = argparse.ArgumentParser(
        description="Pre-gather context for duplicate checking",
    )
    parser.add_argument("--report", required=True, help="Path to report file")
    parser.add_argument("--output-dir", required=True, help="Output directory")
    args = parser.parse_args()

    current_issue = int(os.environ.get("ISSUE_NUMBER", "0"))

    os.makedirs(args.output_dir, exist_ok=True)
    issues_dir = os.path.join(args.output_dir, "issues")
    os.makedirs(issues_dir, exist_ok=True)

    # Extract report metadata
    print("  Extracting report metadata...")
    report_meta = extract_report_metadata(args.report)
    with open(os.path.join(args.output_dir, "report-metadata.json"), "w") as f:
        json.dump(report_meta, f, indent=2)
    print(
        f"    {len(report_meta['ghsa_ids'])} GHSA IDs, "
        f"{len(report_meta['cve_ids'])} CVE IDs, "
        f"{len(report_meta['file_paths'])} file paths, "
        f"{len(report_meta['vulnerability_keywords'])} keywords"
    )

    # Fetch and index existing issues (excluding the current one)
    print("  Fetching existing issues...")
    issues = fetch_existing_issues()
    issues = [i for i in issues if i["number"] != current_issue]

    index = [build_index_entry(i) for i in issues]
    with open(os.path.join(args.output_dir, "index.json"), "w") as f:
        json.dump(index, f, indent=2)
    print(f"    {len(index)} existing issues indexed")

    # Write individual issue bodies for on-demand reading
    for issue in issues:
        path = os.path.join(issues_dir, f"{issue['number']}.md")
        with open(path, "w") as f:
            f.write(issue.get("body", ""))

    # Check for exact matches
    exact = find_exact_matches(report_meta, index)
    with open(os.path.join(args.output_dir, "exact-matches.json"), "w") as f:
        json.dump(exact, f, indent=2)

    if exact:
        print(f"    EXACT MATCHES: {len(exact)} found")
        for m in exact:
            print(f"      #{m['issue_number']}: {m['match_type']}={m['match_value']}")
    else:
        print("    No exact matches")


if __name__ == "__main__":
    main()
