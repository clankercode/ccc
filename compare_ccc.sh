#!/bin/bash
# compare_ccc.sh — run all language ccc binaries in parallel and compare outputs
set -euo pipefail

TIMEOUT="${2:-30}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PROMPT="${1:?usage: $0 '<prompt>' [timeout_seconds]}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MOCK="$ROOT/tests/mock-coding-cli/mock_coding_cli.sh"

if [ ! -x "$MOCK" ]; then
    echo "mock binary not found at $MOCK" >&2
    exit 1
fi

BIN_DIR="$TMPDIR/bin"
mkdir -p "$BIN_DIR"
ln -sf "$MOCK" "$BIN_DIR/opencode"

declare -A LANGUAGES
LANGUAGES[Python]="python3 python/call_coding_clis/cli.py"
LANGUAGES[Rust]="target/debug/ccc"
LANGUAGES[TypeScript]="node typescript/src/ccc.js"
LANGUAGES[C]="c/build/ccc"
LANGUAGES[Go]="go/ccc"
LANGUAGES[Ruby]="ruby ruby/bin/ccc"
LANGUAGES[Perl]="perl -Iperl/lib perl/bin/ccc"
LANGUAGES["C++"]="cpp/build/ccc"
LANGUAGES[Zig]="zig/zig-out/bin/ccc"
LANGUAGES[D]="d/ccc"
LANGUAGES["F#"]="dotnet run --project fsharp/src/App --"
LANGUAGES[PHP]="php php/bin/ccc"
LANGUAGES[ASM]="asm-x86_64/ccc"
LANGUAGES[OCaml]="ocaml/_build/default/bin/ccc.exe"
LANGUAGES[Elixir]=""
LANGUAGES[Nim]=""
LANGUAGES[Crystal]=""
LANGUAGES[Haskell]=""
LANGUAGES[VBScript]=""
LANGUAGES[PureScript]=""

declare -A ENV_OVERRIDE
ENV_OVERRIDE[Python]="PYTHONPATH=$ROOT/python PATH=$BIN_DIR:$(printenv PATH)"
ENV_OVERRIDE[ASM]="CCC_REAL_OPENCODE=$BIN_DIR/opencode PATH=$BIN_DIR:$(printenv PATH)"
ENV_OVERRIDE[OCaml]="CCC_REAL_OPENCODE=$BIN_DIR/opencode PATH=$BIN_DIR:$(printenv PATH)"

BASE_ENV="PATH=$BIN_DIR:$(printenv PATH)"

echo ""
printf "${BOLD}ccc comparison: '%s'${RESET}\n" "$PROMPT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PIDS=()
NAMES=()
ORDERED_LANGS="Python Rust TypeScript C Go Ruby Perl C++ Zig D F# PHP ASM OCaml"

for lang in $ORDERED_LANGS; do
    cmd="${LANGUAGES[$lang]:-}"
    if [ -z "$cmd" ]; then
        printf "${YELLOW}%-12s SKIP${RESET}\n" "$lang"
        continue
    fi

    outfile="$TMPDIR/${lang}.out"
    errfile="$TMPDIR/${lang}.err"
    rcfile="$TMPDIR/${lang}.rc"
    NAMES+=("$lang")

    env_str="${ENV_OVERRIDE[$lang]:-$BASE_ENV}"

    (
        export $env_str
        rc=0
        timeout "$TIMEOUT" $cmd "$PROMPT" > "$outfile" 2> "$errfile" || rc=$?
        echo "$rc" > "$rcfile"
    ) &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

REF_EXIT=""
REF_STDOUT=""
FIRST_LANG=""

PASS=0
FAIL=0
SKIP=0

printf "${BOLD}%-12s %-8s %-40s %-10s${RESET}\n" "Language" "Exit" "Stdout" "Match"
echo "────────────────────────────────────────────────────────────────────"

for i in "${!NAMES[@]}"; do
    lang="${NAMES[$i]}"
    outfile="$TMPDIR/${lang}.out"
    errfile="$TMPDIR/${lang}.err"
    rcfile="$TMPDIR/${lang}.rc"

    if [ ! -f "$rcfile" ]; then
        printf "${YELLOW}%-12s %-8s %-40s %-10s${RESET}\n" "$lang" "SKIP" "-" "-"
        SKIP=$((SKIP + 1))
        continue
    fi

    rc=$(cat "$rcfile")
    stdout=$(cat "$outfile")
    stderr=$(cat "$errfile")

    if [ "$rc" = "124" ]; then
        printf "${YELLOW}%-12s %-8s %-40s %-10s${RESET}\n" "$lang" "TIMEOUT" "-" "-"
        SKIP=$((SKIP + 1))
        continue
    fi

    if [ -z "$FIRST_LANG" ]; then
        FIRST_LANG="$lang"
        REF_EXIT="$rc"
        REF_STDOUT="$stdout"
        printf "${GREEN}%-12s %-8s %-40s %-10s${RESET}\n" "$lang" "$rc" "$(echo "$stdout" | head -c 38)" "REF"
        PASS=$((PASS + 1))
        continue
    fi

    match="YES"
    color="$GREEN"

    if [ "$rc" != "$REF_EXIT" ]; then
        match="NO(exit)"
        color="$RED"
    elif [ "$stdout" != "$REF_STDOUT" ]; then
        match="NO(out)"
        color="$RED"
    fi

    if [ "$match" = "YES" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    printf "${color}%-12s %-8s %-40s %-10s${RESET}\n" "$lang" "$rc" "$(echo "$stdout" | head -c 38)" "$match"

    if [ "$match" != "YES" ]; then
        echo "  ${DIM}Expected: $(echo "$REF_STDOUT" | head -c 60)${RESET}"
        echo "  ${DIM}Got:      $(echo "$stdout" | head -c 60)${RESET}"
        if [ -s "$errfile" ]; then
            echo "  ${DIM}Stderr:   $(echo "$stderr" | head -c 80)${RESET}"
        fi
    fi
done

echo ""
total=$((PASS + FAIL + SKIP))
printf "  Total: %d  ${GREEN}Pass: %d${RESET}  ${RED}Fail: %d${RESET}  ${YELLOW}Skip: %d${RESET}\n" "$total" "$PASS" "$FAIL" "$SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
