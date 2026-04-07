#!/bin/bash
# run_all_tests.sh — unified test runner for all call-coding-clis implementations
# Runs every language's tests and the cross-language harness, then prints a summary.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
PASS=0
FAIL=0
SKIP=0
RESULTS=()

run_test() {
    local label="$1"
    local cmd="$2"
    local logfile="$3"

    printf "  ${DIM}Running:${RESET} %-45s " "$label"
    if eval "$cmd" >"$logfile" 2>&1; then
        printf "${GREEN}PASS${RESET}\n"
        PASS=$((PASS + 1))
        RESULTS+=("${GREEN}PASS${RESET}|${label}")
    else
        printf "${RED}FAIL${RESET}\n"
        FAIL=$((FAIL + 1))
        RESULTS+=("${RED}FAIL${RESET}|${label}")
        tail -5 "$logfile" | sed 's/^/        /'
    fi
}

skip_test() {
    local label="$1"
    local reason="$2"
    printf "  ${YELLOW}SKIP${RESET}  %-45s ${DIM}(%s)${RESET}\n" "$label" "$reason"
    SKIP=$((SKIP + 1))
    RESULTS+=("${YELLOW}SKIP${RESET}|${label}")
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo ""
printf "${BOLD}call-coding-clis — Unified Test Runner${RESET}\n"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

printf "${BOLD}[1/10] Python — unit tests${RESET}\n"
run_test "python: runner + prompt_spec" \
    "PYTHONPATH=python python3 -m unittest tests.test_runner -v" \
    "$TMPDIR/python_unit.log"

printf "\n${BOLD}[2/10] Rust — unit tests${RESET}\n"
run_test "rust: cargo test" \
    "(cd rust && cargo test 2>&1)" \
    "$TMPDIR/rust_unit.log"

printf "\n${BOLD}[3/10] TypeScript — unit tests${RESET}\n"
run_test "typescript: node --test" \
    "node --test typescript/tests/runner.test.mjs 2>&1" \
    "$TMPDIR/ts_unit.log"

printf "\n${BOLD}[4/10] C — unit tests${RESET}\n"
run_test "c: make test" \
    "make -C c test 2>&1" \
    "$TMPDIR/c_unit.log"

printf "\n${BOLD}[5/10] Go — unit tests${RESET}\n"
run_test "go: go test" \
    "(cd go && go test ./... && go vet ./...) 2>&1" \
    "$TMPDIR/go_unit.log"

printf "\n${BOLD}[6/10] Ruby — unit tests${RESET}\n"
run_test "ruby: test suite" \
    "(cd ruby && ruby -Ilib -Itest test/test_*.rb) 2>&1" \
    "$TMPDIR/ruby_unit.log"

printf "\n${BOLD}[7/10] Perl — unit tests${RESET}\n"
run_test "perl: prove" \
    "(cd perl && prove -v t/) 2>&1" \
    "$TMPDIR/perl_unit.log"

printf "\n${BOLD}[8/10] C++ — unit tests${RESET}\n"
run_test "cpp: cmake build + gtest" \
    "(cmake -B cpp/build -S cpp >/dev/null 2>&1 && cmake --build cpp/build --target ccc_tests >/dev/null 2>&1 && ./cpp/build/tests/ccc_tests) 2>&1" \
    "$TMPDIR/cpp_unit.log"

printf "\n${BOLD}[9/10] Cross-language contract tests${RESET}\n"
run_test "contract: ccc CLI behavior (8 languages)" \
    "PYTHONPATH=python python3 -m unittest tests.test_ccc_contract -v 2>&1" \
    "$TMPDIR/contract.log"

printf "\n${BOLD}[10/10] Cross-language harness (mock-coding-cli)${RESET}\n"
run_test "harness: mock binary behavior (8 langs × 9 cases)" \
    "PYTHONPATH=python python3 -m unittest tests.test_harness -v 2>&1" \
    "$TMPDIR/harness.log"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "${BOLD}Summary${RESET}\n"
echo ""

for entry in "${RESULTS[@]}"; do
    status="${entry%%|*}"
    label="${entry#*|}"
    printf "  %b  %s\n" "$status" "$label"
done

echo ""
total=$((PASS + FAIL + SKIP))
printf "  Total: %d  ${GREEN}Passed: %d${RESET}  ${RED}Failed: %d${RESET}  ${YELLOW}Skipped: %d${RESET}\n" "$total" "$PASS" "$FAIL" "$SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
    printf "${RED}${BOLD}FAILURES DETECTED${RESET}\n\n"
    exit 1
fi

printf "${GREEN}${BOLD}ALL TESTS PASSING${RESET}\n\n"
exit 0
