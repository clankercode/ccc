#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [ "$#" -ne 1 ]; then
    echo "usage: ./test_impl.sh <language|all>" >&2
    exit 2
fi

LANGUAGE="$1"

run_unit_tests() {
    case "$LANGUAGE" in
        all)
            return 0
            ;;
        python)
            PYTHONPATH=python python3 -m unittest tests.test_runner -v
            ;;
        rust)
            (cd rust && cargo test)
            ;;
        typescript|ts)
            node --test typescript/tests/runner.test.mjs
            ;;
        c)
            make -C c test
            ;;
        go)
            (cd go && go test ./... && go vet ./...)
            ;;
        ruby)
            (cd ruby && ruby -Ilib -Itest test/test_*.rb)
            ;;
        perl)
            (cd perl && prove -v t/)
            ;;
        cpp|c++)
            cmake -B cpp/build -S cpp
            cmake --build cpp/build --target ccc_tests
            ./cpp/build/tests/ccc_tests
            ;;
        zig)
            (cd zig && zig build test)
            ;;
        crystal)
            (cd crystal && PATH=/usr/bin:$PATH crystal spec)
            ;;
        d)
            (cd d && PATH=/usr/bin:$PATH dub test)
            ;;
        fsharp|f#)
            (cd fsharp && dotnet test)
            ;;
        php)
            (cd php && php tests/RunnerTest.php)
            ;;
        purescript)
            (cd purescript && spago test)
            ;;
        asm|x86-64-asm)
            (cd asm-x86_64 && bash tests/test_ccc.sh)
            ;;
        ocaml)
            (cd ocaml && eval "$(opam env)" && dune runtest)
            ;;
        elixir)
            (cd elixir && mix test)
            ;;
        nim)
            (cd nim && for t in tests/test_*.nim; do PATH=/usr/bin:/home/xertrov/.nimble/bin:$PATH nim c -r --path:src --path:. "$t"; done)
            ;;
        haskell)
            (cd haskell && cabal test call-coding-clis-test)
            ;;
        *)
            echo "unknown language '$LANGUAGE'" >&2
            exit 2
            ;;
    esac
}

if [ "$LANGUAGE" = "all" ]; then
    ./run_all_tests.sh
    exit 0
fi

run_unit_tests
PYTHONPATH=python python3 tests/test_ccc_contract_impl.py "$LANGUAGE" -v
PYTHONPATH=python python3 tests/test_harness.py "$LANGUAGE" -v
