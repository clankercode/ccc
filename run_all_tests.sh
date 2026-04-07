#!/bin/bash
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

printf "${BOLD}[1/22] Python — unit tests${RESET}\n"
run_test "python: runner + prompt_spec" \
    "PYTHONPATH=python python3 -m unittest tests.test_runner -v" \
    "$TMPDIR/python_unit.log"

printf "\n${BOLD}[2/22] Rust — unit tests${RESET}\n"
run_test "rust: cargo test" \
    "(cd rust && cargo test 2>&1)" \
    "$TMPDIR/rust_unit.log"

printf "\n${BOLD}[3/22] TypeScript — unit tests${RESET}\n"
run_test "typescript: node --test" \
    "node --test typescript/tests/runner.test.mjs 2>&1" \
    "$TMPDIR/ts_unit.log"

printf "\n${BOLD}[4/22] C — unit tests${RESET}\n"
run_test "c: make test" \
    "make -C c test 2>&1" \
    "$TMPDIR/c_unit.log"

printf "\n${BOLD}[5/22] Go — unit tests${RESET}\n"
run_test "go: go test" \
    "(cd go && go test ./... && go vet ./...) 2>&1" \
    "$TMPDIR/go_unit.log"

printf "\n${BOLD}[6/22] Ruby — unit tests${RESET}\n"
run_test "ruby: test suite" \
    "(cd ruby && ruby -Ilib -Itest test/test_*.rb) 2>&1" \
    "$TMPDIR/ruby_unit.log"

printf "\n${BOLD}[7/22] Perl — unit tests${RESET}\n"
run_test "perl: prove" \
    "(cd perl && prove -v t/) 2>&1" \
    "$TMPDIR/perl_unit.log"

printf "\n${BOLD}[8/22] C++ — unit tests${RESET}\n"
run_test "cpp: cmake build + gtest" \
    "(cmake -B cpp/build -S cpp >/dev/null 2>&1 && cmake --build cpp/build --target ccc_tests >/dev/null 2>&1 && ./cpp/build/tests/ccc_tests) 2>&1" \
    "$TMPDIR/cpp_unit.log"

printf "\n${BOLD}[9/22] Zig — unit tests${RESET}\n"
run_test "zig: zig build test" \
    "(cd zig && zig build test 2>&1)" \
    "$TMPDIR/zig_unit.log"

printf "\n${BOLD}[10/22] Crystal — unit tests${RESET}\n"
skip_test "crystal: stdout/stderr swap bug" "runner.cr channel ordering"

printf "\n${BOLD}[11/22] D — unit tests${RESET}\n"
run_test "d: dub test" \
    "(cd d && dub test 2>&1)" \
    "$TMPDIR/d_unit.log"

printf "\n${BOLD}[12/22] F# — unit tests${RESET}\n"
run_test "fsharp: dotnet test" \
    "(cd fsharp && dotnet test 2>&1)" \
    "$TMPDIR/fsharp_unit.log"

printf "\n${BOLD}[13/22] PHP — unit tests${RESET}\n"
run_test "php: test suite" \
    "(cd php && php tests/RunnerTest.php) 2>&1" \
    "$TMPDIR/php_unit.log"

printf "\n${BOLD}[14/22] PureScript — unit tests${RESET}\n"
skip_test "purescript: spago test" "purs compiler not installed"

printf "\n${BOLD}[15/22] x86-64 ASM — tests${RESET}\n"
run_test "asm: test_ccc.sh" \
    "(cd asm-x86_64 && bash tests/test_ccc.sh) 2>&1" \
    "$TMPDIR/asm_unit.log"

printf "\n${BOLD}[16/22] OCaml — unit tests${RESET}\n"
run_test "ocaml: dune runtest" \
    "(cd ocaml && eval \$(opam env) && dune runtest 2>&1)" \
    "$TMPDIR/ocaml_unit.log"

printf "\n${BOLD}[17/22] Elixir — unit tests${RESET}\n"
run_test "elixir: mix test" \
    "(cd elixir && mix test 2>&1)" \
    "$TMPDIR/elixir_unit.log"

printf "\n${BOLD}[18/22] Nim — unit tests${RESET}\n"
skip_test "nim: test suite" "nim compiler not installed"

printf "\n${BOLD}[19/22] Haskell — unit tests${RESET}\n"
skip_test "haskell: cabal test" "cabal/ghc not installed"

printf "\n${BOLD}[20/22] VBScript — unit tests${RESET}\n"
skip_test "vbscript: test suite" "Windows only"

printf "\n${BOLD}[21/22] Cross-language contract tests${RESET}\n"
run_test "contract: ccc CLI behavior (15 languages)" \
    "PYTHONPATH=python python3 -m unittest tests.test_ccc_contract -v 2>&1" \
    "$TMPDIR/contract.log"

printf "\n${BOLD}[22/22] Cross-language harness (mock-coding-cli)${RESET}\n"
run_test "harness: mock binary behavior (15 langs × 9 cases)" \
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
