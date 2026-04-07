#!/bin/sh
# mock-coding-cli — deterministic mock for cross-language test harness
# Replaces "opencode" during testing. Reacts to known prompts with fixed outputs.
#
# Usage: mock_coding_cli.sh [run] "<prompt>"
# If stdin starts with "PROMPT:", echo the remainder and exit.
# Otherwise, match argv against the prompt table below.

# --- stdin check (takes priority) ---
stdin_data=""
if [ -t 0 ] 2>/dev/null; then
    : # no stdin
else
    stdin_data=$(cat)
fi

case "$stdin_data" in
    PROMPT:\ *)
        text=$(printf '%s' "$stdin_data" | sed 's/^PROMPT: //')
        printf 'mock: stdin received: %s\n' "$text"
        exit 0
        ;;
esac

# --- argv parsing ---
# The ccc CLIs invoke: opencode run "<prompt>"
# So $1=run $2=<prompt>, or just $1=<prompt> for direct testing

if [ "$1" = "run" ]; then
    shift
fi

prompt="$*"

# --- prompt table ---
case "$prompt" in
    "hello world")
        printf 'mock: ok\n'
        exit 0
        ;;
    "Fix the failing tests")
        printf 'opencode run Fix the failing tests\n'
        exit 0
        ;;
    "exit 42")
        printf 'mock: intentional failure\n' >&2
        exit 42
        ;;
    "stderr test")
        printf 'mock: stdout output\n'
        printf 'mock: stderr output\n' >&2
        exit 0
        ;;
    "multiline")
        printf 'line1\nline2\nline3\n'
        exit 0
        ;;
    "large output")
        # 4096 A's followed by newline
        yes A | tr -d '\n' | head -c 4096
        printf '\n'
        exit 0
        ;;
    "mixed streams")
        printf 'mock: out\n'
        printf 'mock: err\n' >&2
        exit 1
        ;;
    "special chars \"double\" 'single' & | > < \$backslash")
        printf 'mock: special chars handled\n'
        exit 0
        ;;
    "")
        printf 'usage: opencode run "<Prompt>"\n' >&2
        exit 1
        ;;
    *)
        printf "mock: unknown prompt '%s'\n" "$prompt"
        exit 0
        ;;
esac
