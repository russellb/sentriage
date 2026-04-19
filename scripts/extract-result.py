#!/usr/bin/env python3
"""Extract structured JSON result from Claude's stream-json output.

Reads the stream-json FIFO output (captured to a file), extracts the
final text content, parses it as JSON, and writes individual fields
to an output directory for the GitHub Action to read.

Usage: extract-result.py <stream-output-file> <output-dir>
"""

import json
import os
import sys


def extract_text_from_stream(stream_file):
    """Reassemble the full text content from stream-json deltas."""
    text = ""
    with open(stream_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue

            msg_type = msg.get("type")
            if msg_type != "stream_event":
                continue

            event = msg.get("event", {})
            event_type = event.get("type")

            if event_type == "content_block_delta":
                delta = event.get("delta", {})
                if delta.get("type") == "text_delta":
                    text += delta.get("text", "")

    return text


def parse_result(text):
    """Parse the JSON result from Claude's text output.

    Claude may wrap JSON in markdown code fences — strip them if present.
    """
    stripped = text.strip()

    if stripped.startswith("```"):
        lines = stripped.split("\n")
        start = 1
        if lines[0].startswith("```json"):
            start = 1
        end = len(lines) - 1
        if lines[end].strip() == "```":
            end = end
        stripped = "\n".join(lines[start:end]).strip()

    return json.loads(stripped)


def write_outputs(result, output_dir):
    """Write structured fields to individual files in output_dir."""
    os.makedirs(output_dir, exist_ok=True)

    fields = {
        "recommendation": str(result.get("recommendation", "unknown")),
        "confidence": str(result.get("confidence", 0.0)),
        "severity": str(result.get("severity", "unknown")),
        "manipulation_detected": str(result.get("manipulation_detected", False)).lower(),
        "analysis": str(result.get("analysis", "")),
    }

    for field, value in fields.items():
        with open(os.path.join(output_dir, field), "w") as f:
            f.write(value)

    with open(os.path.join(output_dir, "result.json"), "w") as f:
        json.dump(result, f, indent=2)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <stream-output-file> <output-dir>",
              file=sys.stderr)
        sys.exit(1)

    stream_file = sys.argv[1]
    output_dir = sys.argv[2]

    text = extract_text_from_stream(stream_file)
    if not text:
        print("Error: no text content found in stream output", file=sys.stderr)
        sys.exit(1)

    try:
        result = parse_result(text)
    except json.JSONDecodeError as e:
        print(f"Error: could not parse JSON from Claude output: {e}",
              file=sys.stderr)
        print(f"Raw text:\n{text[:500]}", file=sys.stderr)
        sys.exit(1)

    write_outputs(result, output_dir)
    print(f"Result extracted to {output_dir}/", file=sys.stderr)


if __name__ == "__main__":
    main()
