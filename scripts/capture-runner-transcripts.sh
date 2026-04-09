#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/tests/fixtures/runner-transcripts"

mkdir -p "${OUT_DIR}"

echo "Capture helper for real runner transcript fixtures."
echo "Current checked-in fixtures are sanitized excerpts from real 2026-04-09 captures."
echo
echo "Recommended commands:"
echo "  claude -p --verbose --output-format stream-json --include-partial-messages '<prompt>'"
echo "  kimi --print --output-format stream-json --prompt '<prompt>'"
echo "  HOME=/tmp/ccc-opencode-home XDG_DATA_HOME=/tmp/ccc-opencode-xdg-data XDG_CONFIG_HOME=/tmp/ccc-opencode-xdg-config XDG_CACHE_HOME=/tmp/ccc-opencode-xdg-cache XDG_STATE_HOME=/tmp/ccc-opencode-xdg-state opencode run --format json '<prompt>'"
echo
echo "After capture:"
echo "  1. redact session ids, UUIDs, tool ids, and local paths"
echo "  2. trim bootstrap noise that is not parser-relevant"
echo "  3. save prompt.txt, stdout.ndjson/json, stderr.txt, and meta.json under ${OUT_DIR}"
echo
echo "This script is intentionally conservative: it documents the capture contract and stable commands, but does not overwrite fixtures automatically."
