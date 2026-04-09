#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage:
  scripts/smoke-output-modes.sh <python|rust> <cc|k|oc> <formatted|stream-formatted|json|stream-json|text|stream-text> [scenario]

Scenarios:
  toolstorm   Tool-heavy visual smoke test with sleeps and narrated progress
  thinking    Short thinking-oriented prompt
  simple      Minimal response prompt

Examples:
  scripts/smoke-output-modes.sh python cc stream-formatted
  scripts/smoke-output-modes.sh rust k formatted thinking
  scripts/smoke-output-modes.sh python oc formatted simple
EOF
}

if [ "${1:-}" = "" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

impl="${1:-}"
runner="${2:-}"
mode="${3:-}"
scenario="${4:-toolstorm}"

case "$impl" in
    python)
        base_cmd=(python3 "$ROOT/python/call_coding_clis/cli.py")
        export PYTHONPATH="$ROOT/python${PYTHONPATH:+:$PYTHONPATH}"
        ;;
    rust)
        base_cmd=("$ROOT/rust/target/debug/ccc")
        ;;
    *)
        echo "unknown implementation: $impl" >&2
        usage >&2
        exit 1
        ;;
esac

case "$runner" in
    cc|k|oc) ;;
    *)
        echo "unknown runner: $runner" >&2
        usage >&2
        exit 1
        ;;
esac

case "$mode" in
    text|stream-text|json|stream-json|formatted|stream-formatted) ;;
    *)
        echo "unknown output mode: $mode" >&2
        usage >&2
        exit 1
        ;;
esac

case "$scenario" in
    toolstorm)
        prompt='Use tools. First state in one short sentence what you are doing. Then use Bash to compute 987654321987654321 * 123456789123456789. Then use Bash to run `sleep 3`. Then state one short progress sentence. Then use Bash to compute 111111111111111111 * 999999999999999937. Then use Bash to run `sleep 2`. End with exactly DONE on the final line.'
        ;;
    thinking)
        prompt='Think carefully, then answer: what is 987654321987654321 * 123456789123456789? Give the integer and one short sentence.'
        ;;
    simple)
        prompt='Reply in exactly three short lines: alpha, beta, gamma.'
        ;;
    *)
        echo "unknown scenario: $scenario" >&2
        usage >&2
        exit 1
        ;;
esac

cmd=("${base_cmd[@]}" "$runner" "-o" "$mode")
if [ "$runner" = "cc" ]; then
    cmd+=(":anthropic:claude-haiku-4-5")
fi
if [ "$mode" = "formatted" ] || [ "$mode" = "stream-formatted" ]; then
    cmd+=("--show-thinking")
    if [ "${SMOKE_FORWARD_UNKNOWN_JSON:-0}" = "1" ]; then
        cmd+=("--forward-unknown-json")
    fi
fi
cmd+=("$prompt")

printf 'Running smoke command:\n  %q' "${cmd[0]}"
for arg in "${cmd[@]:1}"; do
    printf ' %q' "$arg"
done
printf '\n\n'

exec "${cmd[@]}"
