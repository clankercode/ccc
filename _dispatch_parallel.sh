#!/bin/bash
set -uo pipefail

ROOT="/home/xertrov/src/call-coding-clis"
LOGDIR="$ROOT/.subagent-logs"
mkdir -p "$LOGDIR"
rm -f "$LOGDIR"/*.log

PROMPT_FILE="$LOGDIR/_shared_prompt.txt"
cat > "$PROMPT_FILE" <<'PROMPT_EOF'
You are working on the LANGUAGE implementation of call-coding-clis. Your goal is to fully satisfy the v1 Core Contract defined in INDEX_MASTER_SPEC.md.

INSTRUCTIONS:
1. First, load the ultra-goal-loop skill (use the skill tool with name "ultra-goal-loop").
2. Read the following spec files (they are in the parent directory, use ../ prefix):
   - ../INDEX_MASTER_SPEC.md
   - ../IMPLEMENTATION_REFERENCE.md
   - ../CCC_BEHAVIOR_CONTRACT.md
3. Your acceptance criteria: every v1 feature (F01-F15, F28-F30) must be implemented and passing for your language. Check the feature matrix in ../FEATURES.md to see current status and identify gaps.
4. You are mostly restricted to your own subdirectory, but you may need to edit shared files to wire in your language:
   - tests/test_ccc_contract.py
   - tests/test_harness.py
   - run_all_tests.sh
   - FEATURES.md
   CRITICAL WARNING: Other subagents are working concurrently and may edit the same shared files. If you encounter a git conflict, merge conflict markers, or unexpected file state when reading/writing shared files, run `sleep 30` and retry. Repeat until the issue clears up.
5. You may install necessary dependencies (toolchains, compilers, packages) if not present. Use your best judgment and brainstorm solutions for any environment issues.
6. Scope is v1 ONLY (F01-F15, F28-F30). Do NOT implement v2 or v3 features.
7. After making changes, verify by running the relevant tests for your language.
8. Do NOT commit changes. Just make the changes and ensure tests pass.
PROMPT_EOF

LANGUAGES=(
  "python:python"
  "rust:rust"
  "typescript:typescript"
  "c:c"
  "go:go"
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
  "asm-x86_64:asm-x86_64"
  "elixir:elixir"
  "ocaml:ocaml"
)

echo "=========================================="
echo " Dispatching 19 parallel subagents"
echo " Logs: $LOGDIR"
echo "=========================================="
echo ""

PIDS=()
for entry in "${LANGUAGES[@]}"; do
  LANG="${entry%%:*}"
  DIR="${entry##*:}"

  LANG_PROMPT="$LOGDIR/_prompt_${LANG}.txt"
  sed "s/LANGUAGE/${LANG}/g" "$PROMPT_FILE" > "$LANG_PROMPT"

  echo "[START] $LANG -> $DIR"
  opencode run \
    --model zai-coding-plan/glm-5-turbo \
    --dir "$ROOT/$DIR" \
    "$(cat "$LANG_PROMPT")" \
    > "$LOGDIR/${LANG}.log" 2>&1 &

  PIDS+=($!)
  echo "        PID: ${PIDS[-1]}"
done

echo ""
echo "=========================================="
echo " All 19 subagents launched. Waiting..."
echo "=========================================="
echo ""

FAILED=0
for i in "${!LANGUAGES[@]}"; do
  entry="${LANGUAGES[$i]}"
  LANG="${entry%%:*}"
  PID="${PIDS[$i]}"
  
  if wait "$PID"; then
    echo "[DONE]  $LANG (PID $PID) - SUCCESS"
  else
    echo "[FAIL]  $LANG (PID $PID) - EXIT CODE $?"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=========================================="
echo " Complete. $FAILED failures."
echo " Logs in: $LOGDIR"
echo "=========================================="

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "Failed languages:"
  for entry in "${LANGUAGES[@]}"; do
    LANG="${entry%%:*}"
    if ! grep -q "ultra-goal-loop.*PASS\|All acceptance criteria satisfied\|goal.*satisfied" "$LOGDIR/${LANG}.log" 2>/dev/null; then
      echo "  - $LANG (last 20 lines):"
      tail -20 "$LOGDIR/${LANG}.log" 2>/dev/null | sed 's/^/    /'
    fi
  done
fi

rm -f "$PROMPT_FILE"
for entry in "${LANGUAGES[@]}"; do
  LANG="${entry%%:*}"
  rm -f "$LOGDIR/_prompt_${LANG}.txt"
done

exit $FAILED
