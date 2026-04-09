#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${1:-/tmp/kimi-error-surfaces-${STAMP}}"
PROMPT="${KIMI_CAPTURE_PROMPT:-Reply with exactly pong.}"
TIMEOUT_SECONDS="${KIMI_CAPTURE_TIMEOUT_SECONDS:-120}"

mkdir -p "${OUT_DIR}"

HOME_DIR="${OUT_DIR}/home"
XDG_DATA_HOME="${OUT_DIR}/xdg-data"
XDG_CONFIG_HOME="${OUT_DIR}/xdg-config"
XDG_CACHE_HOME="${OUT_DIR}/xdg-cache"
XDG_STATE_HOME="${OUT_DIR}/xdg-state"

mkdir -p \
  "${HOME_DIR}" \
  "${XDG_DATA_HOME}" \
  "${XDG_CONFIG_HOME}" \
  "${XDG_CACHE_HOME}" \
  "${XDG_STATE_HOME}"

run_capture() {
  local name="$1"
  shift

  local case_dir="${OUT_DIR}/${name}"
  mkdir -p "${case_dir}"

  printf '%s\n' "${PROMPT}" > "${case_dir}/prompt.txt"
  printf '%s\0' "$@" > "${case_dir}/argv.bin"
  printf '%q ' "$@" > "${case_dir}/argv.sh"
  printf '\n' >> "${case_dir}/argv.sh"

  local exit_code=0
  if ! env \
    HOME="${HOME_DIR}" \
    XDG_DATA_HOME="${XDG_DATA_HOME}" \
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
    XDG_CACHE_HOME="${XDG_CACHE_HOME}" \
    XDG_STATE_HOME="${XDG_STATE_HOME}" \
    timeout "${TIMEOUT_SECONDS}s" "$@" >"${case_dir}/stdout.txt" 2>"${case_dir}/stderr.txt" </dev/null; then
    exit_code=$?
  fi

  printf '%s\n' "${exit_code}" > "${case_dir}/exit_code.txt"
}

run_capture raw_text kimi --prompt "${PROMPT}"
run_capture print_text kimi --print --output-format text --prompt "${PROMPT}"
run_capture stream_json kimi --print --output-format stream-json --prompt "${PROMPT}"

cat > "${OUT_DIR}/README.txt" <<EOF
Raw Kimi error-surface capture.

Prompt: ${PROMPT}
Timeout: ${TIMEOUT_SECONDS}s

Cases:
- raw_text: default Kimi stdout/stderr shape used by \`ccc\` text and stream-text modes
- print_text: explicit \`--print --output-format text\` non-interactive text shape
- stream_json: \`--print --output-format stream-json\` shape used by \`ccc\` stream-json, formatted, and stream-formatted modes

Review and redact before copying anything into tests/fixtures/runner-transcripts/.
EOF

printf '%s\n' "${OUT_DIR}"
