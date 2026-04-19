#!/bin/bash
# Container bootstrap: install deps, create non-root user, install Claude Code.
# Adapted from rfe-assessor/scripts/setup-claude-ci.sh.
#
# Auth backend setup (API keys, GCP credentials, etc.) is the caller's
# responsibility — pass credentials via environment variables.
#
# Expected env vars:
#   WORKSPACE_DIR (default: /workspace) — working directory for the agent
set -euo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

microdnf install -y --nodocs git-core shadow-utils util-linux python3 python3-pip diffutils
useradd -m claude-ci
curl -fsSL https://claude.ai/install.sh | runuser -l claude-ci -c bash

if [ -d "$WORKSPACE_DIR" ]; then
  chown -R claude-ci:claude-ci "$WORKSPACE_DIR"
  runuser -u claude-ci -- git config --global --add safe.directory "$WORKSPACE_DIR"
fi
