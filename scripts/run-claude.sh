#!/bin/bash
# Wrapper script for running Claude in CI with streaming and telemetry.
# Adapted from rfe-assessor/scripts/run-claude.sh.
#
# Usage: run-claude.sh <prompt> [workdir]
#
# When run as root, re-execs itself as the claude-ci user.
# Starts OTEL collector, runs Claude with FIFO-based streaming,
# and prints a token/cost summary on completion.
set -euo pipefail

# Re-exec as claude-ci when running as root
if [ "$(id -u)" -eq 0 ]; then
  exec runuser -u claude-ci -- bash "$0" "$@"
fi

export PATH="$HOME/.local/bin:$PATH"

echo "--- Preflight checks ---"
claude --version

ci_scripts="$(cd "$(dirname "$0")" && pwd)"
workdir="${2:-.}"
cd "$workdir"

# Install Python dependencies if requirements.txt exists
if [ -f requirements.txt ]; then
  echo "--- Installing Python dependencies ---"
  pip3 install -r requirements.txt --index-url "${PIP_INDEX_URL:-https://pypi.org/simple/}"
fi

# Start OTEL collector to capture token/cost metrics
export OTEL_LOG_FILE="/tmp/claude-otel.jsonl"
rm -f "$OTEL_LOG_FILE"
python3 "$ci_scripts/otel-collector.py" &
otel_pid=$!
echo "--- OTEL collector started (pid $otel_pid) ---"

# Configure Claude to export OTEL data to our local collector
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/json
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
export OTEL_METRIC_EXPORT_INTERVAL=10000

set +e
claude_fifo="/tmp/claude-stream.fifo"
stream_capture="${STREAM_CAPTURE_FILE:-/tmp/claude-stream-capture.jsonl}"
rm -f "$claude_fifo" "$stream_capture"
mkfifo "$claude_fifo"

claude -p "${1:?Usage: $0 <prompt> [workdir]}" \
  --model "${CLAUDE_MODEL:-claude-opus-4-6}" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --include-partial-messages \
  --verbose 2>/tmp/claude-stderr.log | tee "$stream_capture" > "$claude_fifo" &
claude_pid=$!

python3 -u "$ci_scripts/stream-claude.py" --claude-pid "$claude_pid" < "$claude_fifo"
stream_rc=$?

# Ensure Claude is terminated after stream processing completes.
kill "$claude_pid" 2>/dev/null
wait "$claude_pid" 2>/dev/null
rc=$?

# SIGTERM produces exit code 143 (128+15).  Treat as success when
# stream-claude.py detected completion.
if [ "$stream_rc" -eq 0 ] && [ "$rc" -ne 0 ]; then
  echo "--- stream-claude.py detected run complete (claude rc=$rc), treating as success ---"
  rc=0
fi

rm -f "$claude_fifo"

# Wait for Claude's final OTEL flush (CLAUDE_CODE_OTEL_FLUSH_TIMEOUT_MS, default 5s)
sleep 7

# Stop OTEL collector and print summary
kill $otel_pid 2>/dev/null
wait $otel_pid 2>/dev/null

echo "--- Claude exit code: $rc ---"
echo "--- stderr log ---"
cat /tmp/claude-stderr.log >&2

echo ""
echo "--- OTEL Token/Cost Summary ---"
python3 "$ci_scripts/otel-summary.py" "$OTEL_LOG_FILE"

# Copy artifacts for CI artifact upload (GitHub Actions or GitLab CI)
artifact_dir="${GITHUB_WORKSPACE:-${CI_PROJECT_DIR:-}}"
if [ -n "$artifact_dir" ]; then
  cp -f /tmp/claude-otel.jsonl "$artifact_dir/claude-otel.jsonl" 2>/dev/null || true
  cp -f /tmp/claude-stderr.log "$artifact_dir/claude-stderr.log" 2>/dev/null || true
fi

exit $rc
