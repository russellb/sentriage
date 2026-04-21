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

# Per-run temp directory for ephemeral artifacts (FIFO, OTEL, stderr).
# Defaults to $WORKSPACE_DIR/_run when WORKSPACE_DIR is set, otherwise
# creates a unique mktemp directory.
if [ -n "${WORKSPACE_DIR:-}" ]; then
  run_tmp="$WORKSPACE_DIR/_run"
else
  run_tmp="$(mktemp -d /tmp/sentriage-run.XXXXXX)"
fi
mkdir -p "$run_tmp"

# Install Python dependencies if requirements.txt exists
if [ -f requirements.txt ]; then
  echo "--- Installing Python dependencies ---"
  pip3 install -r requirements.txt --index-url "${PIP_INDEX_URL:-https://pypi.org/simple/}"
fi

# Start OTEL collector to capture token/cost metrics.
# Bind to port 0 (OS-assigned) and write the actual port to a file so
# we can point Claude's OTEL exporter at it.
export OTEL_LOG_FILE="$run_tmp/claude-otel.jsonl"
export OTEL_RATE_FILE="$run_tmp/claude-otel-rate.json"
export OTEL_COLLECTOR_PORT=0
export OTEL_PORT_FILE="$run_tmp/otel-port"
rm -f "$OTEL_LOG_FILE" "$OTEL_PORT_FILE"
python3 "$ci_scripts/otel-collector.py" &
otel_pid=$!

# Wait for the collector to write its actual port (up to 5s)
for _ in $(seq 50); do
  [ -f "$OTEL_PORT_FILE" ] && break
  sleep 0.1
done
if [ ! -f "$OTEL_PORT_FILE" ]; then
  echo "Error: OTEL collector did not write port file" >&2
  kill $otel_pid 2>/dev/null
  exit 1
fi
otel_port=$(cat "$OTEL_PORT_FILE")
echo "--- OTEL collector started (pid $otel_pid, port $otel_port) ---"

# Configure Claude to export OTEL data to our local collector
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/json
export OTEL_EXPORTER_OTLP_ENDPOINT="http://127.0.0.1:${otel_port}"
export OTEL_METRIC_EXPORT_INTERVAL=10000

set +e
claude_fifo="$run_tmp/claude-stream.fifo"
stream_capture="${STREAM_CAPTURE_FILE:-$run_tmp/claude-stream-capture.jsonl}"
rm -f "$claude_fifo" "$stream_capture"
mkfifo "$claude_fifo"

claude -p "${1:?Usage: $0 <prompt> [workdir]}" \
  --model "${CLAUDE_MODEL:-claude-opus-4-6}" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --include-partial-messages \
  --verbose 2>"$run_tmp/claude-stderr.log" | tee "$stream_capture" > "$claude_fifo" &
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
cat "$run_tmp/claude-stderr.log" >&2

echo ""
echo "--- OTEL Token/Cost Summary ---"
python3 "$ci_scripts/otel-summary.py" "$OTEL_LOG_FILE"

# Copy artifacts for CI artifact upload (GitHub Actions or GitLab CI)
artifact_dir="${GITHUB_WORKSPACE:-${CI_PROJECT_DIR:-}}"
if [ -n "$artifact_dir" ]; then
  cp -f "$run_tmp/claude-otel.jsonl" "$artifact_dir/claude-otel.jsonl" 2>/dev/null || true
  cp -f "$run_tmp/claude-stderr.log" "$artifact_dir/claude-stderr.log" 2>/dev/null || true
fi

exit $rc
