#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export HOME="/tmp/ccc-test-home"
export XDG_CONFIG_HOME="/tmp/ccc-test-xdg-config"
export XDG_CACHE_HOME="/tmp/ccc-test-xdg-cache"
export XDG_DATA_HOME="/tmp/ccc-test-xdg-data"
export XDG_STATE_HOME="/tmp/ccc-test-xdg-state"
export CCC_CONFIG="/tmp/ccc-test-missing-config.toml"
export GOCACHE="/tmp/ccc-go-cache"
export ZIG_GLOBAL_CACHE_DIR="/tmp/ccc-zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="/tmp/ccc-zig-local-cache"
export DOTNET_CLI_HOME="/tmp/ccc-dotnet-home"
export NUGET_PACKAGES="/tmp/ccc-nuget"
export CRYSTAL_CACHE_DIR="/tmp/ccc-crystal-cache"
export CABAL_DIR="/tmp/ccc-cabal"
export LC_ALL=C
export PERL_BADLANG=0
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
mkdir -p \
    "$HOME" \
    "$XDG_CONFIG_HOME" \
    "$XDG_CACHE_HOME" \
    "$XDG_DATA_HOME" \
    "$XDG_STATE_HOME" \
    "$GOCACHE" \
    "$ZIG_GLOBAL_CACHE_DIR" \
    "$ZIG_LOCAL_CACHE_DIR" \
    "$DOTNET_CLI_HOME" \
    "$NUGET_PACKAGES" \
    "$CRYSTAL_CACHE_DIR" \
    "$CABAL_DIR"

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
            PYTHONPATH=python python3 -m unittest tests.test_runner tests.test_json_output tests.test_parser_config tests.test_ccc_contract -v
            ;;
        rust)
            (cd rust && cargo test)
            ;;
        typescript|ts)
            node --test typescript/tests/*.mjs
            ;;
        c)
            CC=/usr/bin/gcc make -C c test
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
            (cd php && for t in tests/*Test.php; do php "$t"; done)
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
