#!/bin/bash
set -uo pipefail

ROOT="/home/xertrov/src/call-coding-clis"
LOGDIR="$ROOT/.subagent-logs"
mkdir -p "$LOGDIR"
rm -f "$LOGDIR"/help_*.log

PROMPT_FILE="$LOGDIR/_help_prompt.txt"
cat > "$PROMPT_FILE" <<'EOF'
Add --help/-h support and an enhanced no-args runner checklist to the LANGUAGE implementation of call-coding-clis.

REFERENCE IMPLEMENTATION:
Read ../python/call_coding_clis/help.py and ../python/call_coding_clis/cli.py for the reference implementation.

REQUIREMENTS:
1. `ccc --help` and `ccc -h` should print full help text to stdout and exit 0
2. Running `ccc` with no arguments should print a usage line to stderr followed by a runner availability checklist, then exit 1
3. The runner checklist checks which of these 5 runners are on PATH: opencode, claude, kimi, codex, crush
4. For each found runner, run `<binary> --version` (3s timeout) and show the version
5. The help text must include these sections: Usage, Slots (runner, +thinking, :provider:model, @alias), Examples, Config, and the runner checklist

EXACT HELP TEXT (all implementations must match this):
```
ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @alias        Use a named preset from config

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
  ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, aliases, abbreviations
```

After the help text, append the runner checklist.

IMPORTANT:
- Build and test your changes before finishing
- Do NOT edit shared test files (tests/test_ccc_contract.py, tests/test_harness.py)
- Do NOT commit
- If you need to install dependencies, do so
EOF

LANGUAGES=(
  "ruby:ruby"
  "perl:perl"
  "cpp:cpp"
  "zig:zig"
  "d:d"
  "fsharp:fsharp"
  "haskell:haskell"
  "nim:nim"
  "crystal:crystal"
  "php:php"
  "purescript:purescript"
  "elixir:elixir"
  "ocaml:ocaml"
)

echo "=========================================="
echo " Dispatching 13 help subagents"
echo "=========================================="

PIDS=()
for entry in "${LANGUAGES[@]}"; do
  LANG="${entry%%:*}"
  DIR="${entry##*:}"

  LANG_PROMPT="$LOGDIR/_prompt_help_${LANG}.txt"
  sed "s/LANGUAGE/${LANG}/g" "$PROMPT_FILE" > "$LANG_PROMPT"

  echo "[START] $LANG"
  opencode run \
    --model zai-coding-plan/glm-5-turbo \
    --dir "$ROOT/$DIR" \
    "$(cat "$LANG_PROMPT")" \
    > "$LOGDIR/help_${LANG}.log" 2>&1 &

  PIDS+=($!)
done

echo ""
echo "Waiting for all subagents..."
echo ""

FAILED=0
for i in "${!LANGUAGES[@]}"; do
  entry="${LANGUAGES[$i]}"
  LANG="${entry%%:*}"
  PID="${PIDS[$i]}"
  wait "$PID" || FAILED=$((FAILED + 1))
  echo "[DONE]  $LANG (PID $PID)"
done

echo ""
echo "Complete. $FAILED failures."

rm -f "$PROMPT_FILE"
for entry in "${LANGUAGES[@]}"; do
  LANG="${entry%%:*}"
  rm -f "$LOGDIR/_prompt_help_${LANG}.txt"
done

exit $FAILED
