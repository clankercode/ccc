# PureScript Implementation Plan — call-coding-clis

## 1. Project Structure (Spago Package)

```
purescript/
  spago.dhall          # package config, dependencies
  packages.dhall       # package set pin
  src/
    CallCodingClis/
      Types.purs       # CommandSpec, CompletedRun, StreamCallback
      Runner.purs      # Runner.new, Runner.run, Runner.stream
      PromptSpec.purs  # buildPromptSpec
      CCC.purs         # CLI entrypoint (Effect), uses Node.Process
    FFI/
      Spawn.purs       # foreign imports for child_process.spawn
      Spawn.js         # FFI implementation
  test/
    Main.purs          # unit tests (pure: buildPromptSpec, trim, reject)
  output/              # spago build artifact (gitignored)
  .gitignore
  package.json         # bin entry for "ccc" command
```

**Dependencies** (spago.dhall):

```dhall
let upstream =
      https://github.com/purescript/package-sets/releases/download/psc-0.15.11-20240530/packages.dhall sha256:...
in  { name = "call-coding-clis"
    , dependencies =
        [ "prelude"
        , "effect"
        , "node-process"
        , "strings"
        , "console"
        , "aff"
        , "refs"
        , "exceptions"
        , "spec"                  -- test framework
        ]
    , packages = ./packages.dhall
    }
```

Note: There is no maintained `purescript-node-child-process` in recent package sets. Use a thin FFI shim (`src/FFI/Spawn.purs` + `src/FFI/Spawn.js`) wrapping `child_process.spawn` directly.

## 2. Library API

### Types (`src/CallCodingClis/Types.purs`)

```purescript
module CallCodingClis.Types where

import Prelude

type CommandSpec =
  { argv :: Array String
  , stdinText :: Maybe String
  , cwd :: Maybe String
  , env :: StrMap String
  }

type CompletedRun =
  { argv :: Array String
  , exitCode :: Int
  , stdout :: String
  , stderr :: String
  }

type StreamCallback = String -> String -> Effect Unit
```

No newtype wrappers needed — these are simple records matching the other implementations.

### Runner (`src/CallCodingClis/Runner.purs`)

```purescript
newtype Runner = Runner
  { runFn :: CommandSpec -> Aff CompletedRun
  , streamFn :: CommandSpec -> StreamCallback -> Aff CompletedRun
  }

defaultRunner :: Runner
defaultRunner = Runner
  { runFn: runCommand
  , streamFn: streamCommand
  }
```

`run` collects all output then resolves; `stream` fires the callback per chunk then resolves. Both are async (`Aff`) because Node's `child_process.spawn` is event-driven.

### buildPromptSpec (`src/CallCodingClis/PromptSpec.purs`)

```purescript
buildPromptSpec :: String -> Either String CommandSpec
buildPromptSpec prompt =
  let trimmed = String.trim prompt
  in if String.null trimmed
     then Left "prompt must not be empty"
     else Right { argv: ["opencode", "run", trimmed]
                , stdinText: Nothing
                , cwd: Nothing
                , env: empty }
```

The extra `|| String.trim trimmed == ""` guard in the original plan was redundant — `String.null` already handles this after trimming. Returns `Either String CommandSpec` — `Left` on empty/whitespace, `Right` on success. Mirrors Rust's `Result<_, &str>`.

## 3. FFI for Node.js child_process

### Approach: Thin FFI shim

PureScript's standard package sets do not carry `node-child-process`. Write a minimal FFI module wrapping `child_process.spawn`.

**Important**: Use `EffectFn*` imports (uncurried FFI) for correctness and performance. Curried FFI with multiple function arrows creates intermediate closures and risks stack overflow. The `EffectFn4` import maps directly to a JS function taking 4 arguments.

**`src/FFI/Spawn.purs`**:

```purescript
module CallCodingClis.FFI.Spawn where

import Prelude
import Effect (Effect)
import Effect.Uncurried (EffectFn4, runEffectFn4)

type SpawnEvent =
  { tag :: String
  , text :: String
  , exitCode :: Int
  , message :: String
  }

type SpawnOptions =
  { cwd :: Maybe String
  , env :: Maybe (StrMap String)
  , stdinText :: Maybe String
  }

foreign import spawnImpl :: EffectFn4
  String                           -- command
  (Array String)                   -- args
  SpawnOptions                     -- options
  (SpawnEvent -> Effect Unit)      -- onEvent callback
  Unit                             -- returns void

spawn :: String -> Array String -> SpawnOptions -> (SpawnEvent -> Effect Unit) -> Effect Unit
spawn cmd args opts onEvent = runEffectFn4 spawnImpl cmd args opts onEvent
```

**`src/FFI/Spawn.js`**:

```javascript
"use strict";

exports.spawnImpl = function (command) {
  return function (args) {
    return function (opts) {
      return function (onEvent) {
        const child = require("child_process").spawn(command, args, {
          cwd: opts.cwd,
          env: opts.env
            ? Object.assign({}, process.env, opts.env)
            : process.env,
          stdio: "pipe"
        });

        child.stdout.on("data", function (chunk) {
          onEvent({ tag: "Stdout", text: chunk.toString(), exitCode: 0, message: "" });
        });
        child.stderr.on("data", function (chunk) {
          onEvent({ tag: "Stderr", text: chunk.toString(), exitCode: 0, message: "" });
        });
        child.on("close", function (code) {
          onEvent({ tag: "Close", text: "", exitCode: code != null ? code : 1, message: "" });
        });
        child.on("error", function (err) {
          onEvent({ tag: "Error", text: "", exitCode: 1, message: err.message });
        });

        if (opts.stdinText != null) {
          child.stdin.write(opts.stdinText);
        }
        child.stdin.end();
      };
    };
  };
};
```

The JS side uses 4 nested functions (uncurried via `EffectFn4` on the PureScript side). The event object uses a flat record with all fields populated to avoid `Foreign`/`Data.Foreign` parsing overhead.

**Typo fix**: The original plan referenced `require('child_process')` correctly, but the note about `mkAff` callback firing "exactly once" was misleading — see the Aff wrapper section below for the correct cancellation handling.

### Aff wrapper pattern

```purescript
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Effect.Ref as Ref

runSpawn :: String -> Array String -> SpawnOptions -> Aff CompletedRun
runSpawn cmd args opts = makeAff \cb -> do
  stdoutRef <- Ref.new ""
  stderrRef <- Ref.new ""
  let onEvent ev = case ev.tag of
        "Stdout" -> void $ Ref.modify (_ <> ev.text) stdoutRef
        "Stderr" -> void $ Ref.modify (_ <> ev.text) stderrRef
        "Close" -> do
          stdout <- Ref.read stdoutRef
          stderr <- Ref.read stderrRef
          cb $ Right
            { argv: [cmd] <> args
            , exitCode: ev.exitCode
            , stdout
            , stderr
            }
        "Error" -> do
          stderr <- Ref.read stderrRef
          let msg = "failed to start " <> cmd <> ": " <> ev.message <> "\n"
          cb $ Right
            { argv: [cmd] <> args
            , exitCode: 1
            , stdout: ""
            , stderr: msg <> stderr
            }
        _ -> pure unit
  spawn cmd args opts onEvent
  pure nonCanceler
```

**Cancellation**: `nonCanceler` is acceptable here. Node's `child_process.spawn` cannot be externally cancelled once started. The `makeAff` callback `cb` is guaranteed to be called exactly once because Node fires exactly one `close` or `error` event (and never both for the same child process).

**`stream` variant** wraps `runSpawn` but calls `liftEffect $ onEvent "stdout" chunk` / `liftEffect $ onEvent "stderr" chunk` inside the event handler before accumulating.

## 4. ccc CLI as a PureScript-compiled Node.js Entrypoint

**`src/CallCodingClis/CCC.purs`**:

```purescript
module CallCodingClis.CCC where

import Prelude
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (error)
import Node.Process (exit)
import Data.Array (drop, length)
import Data.Maybe (fromMaybe)
import Data.String (null, trim)
import Node.Process as Process
import CallCodingClis.Types (CommandSpec)
import CallCodingClis.PromptSpec (buildPromptSpec)
import CallCodingClis.Runner (defaultRunner)
import CallCodingClis.FFI.Spawn (SpawnOptions)

main :: Effect Unit
main = do
  rawArgs <- Process.argv
  let args = drop 2 rawArgs  -- drop "node" and script path
  case args of
    [prompt] ->
      case buildPromptSpec prompt of
        Left err -> do
          error err
          exit 1
        Right spec -> do
          runnerBinary <- Process.lookupEnv "CCC_REAL_OPENCODE"
          let adjustedSpec = case runnerBinary of
                Nothing -> spec
                Just bin -> spec { argv = [bin] <> drop 1 spec.argv }
          launchAff_ do
            result <- (_.runFn defaultRunner) adjustedSpec
            liftEffect $ exit result.exitCode
    _ -> do
      error "usage: ccc \"<Prompt>\""
      exit 1
```

**`package.json`**:

```json
{
  "name": "call-coding-clis-purescript",
  "bin": {
    "ccc": "output/Node/CallCodingClis/CCC/index.js"
  },
  "private": true
}
```

The CLI entrypoint is compiled to `output/Node/CallCodingClis/CCC/index.js` by `spago build`. To use as `ccc`: either `npm link` from `purescript/`, or invoke directly via `node purescript/output/Node/CallCodingClis/CCC/index.js`.

**Stdout/stderr forwarding**: In the `stream` path, each chunk callback writes directly to `process.stdout`/`process.stderr` via `liftEffect`. The `run` path collects everything and writes at the end. The CLI uses `stream` (like TypeScript) so output appears incrementally.

**Key FFI note on `Node.Process.argv`**: The `node-process` package exposes `argv :: Effect (Array String)`. Import as `Node.Process (argv)` (the `argv` function, not a record field).

**`CCC_REAL_OPENCODE` override**: Read before building argv. If set, replace `argv[0]` ("opencode") with the env var value. This allows contract tests to point at the shell stub.

## 5. Prompt Trimming and Empty Rejection

- Use `Data.String.trim` from the `strings` package.
- After trimming, check `String.null (String.trim prompt)` or `String.trim prompt == ""`.
- PureScript `String.trim` handles all Unicode whitespace, matching the other implementations (Python's `.strip()`, Rust's `.trim()`, etc.).

## 6. Error Format: argv[0] Only

The error string for spawn failure must be exactly:
```
failed to start <argv[0]>: <error_message>\n
```

Where `<argv[0]>` is just the command name (first element of the argv array), not the full argv. This matches all other implementations. The trailing newline is required for consistency with the contract tests.

## 7. Exit Code Forwarding

The CLI must call `process.exit(result.exitCode)` to forward the child process exit code. This is critical because:
- If the child exits with code 42, `ccc` must exit with code 42
- `process.exit()` is the only reliable way in Node.js; `return` from main doesn't work since the event loop may not drain
- PureScript's `Node.Process.exit :: Int -> Effect Unit` maps directly to this

## 8. Test Strategy

### Pure unit tests (`test/Main.purs`)

Use `purescript-spec` for pure tests:

1. **buildPromptSpec tests:**
   - Valid prompt → `Right` with `argv = ["opencode", "run", "Fix the failing tests"]`
   - Empty string → `Left "prompt must not be empty"`
   - Whitespace-only (`"   "`) → `Left "prompt must not be empty"`
   - Prompt with leading/trailing whitespace → trimmed in argv[2]

2. **Trimming edge cases:**
   - Tabs, newlines, mixed whitespace

```bash
spago test
```

### Cross-language contract test registration

Add PureScript entries to each of the four test methods in `tests/test_ccc_contract.py`. The compiled entrypoint is invoked via Node.js:

```python
# In test_cross_language_ccc_happy_path (and similarly for the other 3 test methods):
self.assert_equal_output(
    subprocess.run(
        ["node", "purescript/output/Node/CallCodingClis/CCC/index.js", PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

The four test methods that need PureScript entries:
- `test_cross_language_ccc_happy_path`
- `test_cross_language_ccc_rejects_empty_prompt` (arg: `""`)
- `test_cross_language_ccc_requires_one_prompt_argument` (no args)
- `test_cross_language_ccc_rejects_whitespace_only_prompt` (arg: `"   "`)

No build step is needed in the test file — PureScript output is plain JS files. Ensure `spago build` has been run before the contract tests.

### CCC_REAL_OPENCODE override

The CLI reads `CCC_REAL_OPENCODE` env var. If set, use it as `argv[0]` instead of `"opencode"`. This allows the contract tests to point at the shell stub. The override is applied in `CCC.purs` (see Section 4), not in `buildPromptSpec` — this matches how the TypeScript implementation applies it at the CLI level.

## 9. PureScript-Specific Considerations

### Effect system

- All FFI calls live in `Effect`. Async subprocess work is lifted to `Aff` via `makeAff` / `launchAff_`.
- No need for `Aff` in the pure `buildPromptSpec` function — it returns `Either`.

### FFI safety

- The spawn FFI uses **uncurried** `EffectFn4` to match JS arity exactly. This avoids intermediate closure allocation and the risk of partial application bugs.
- The FFI callback is invoked from Node's event loop. Since `SpawnEvent` is a plain JS object matching a PureScript record type, no `Foreign` parsing is needed — PureScript's FFI auto-unboxes record fields from JS objects.
- `makeAff` callback must invoke `cb` exactly once. The FFI guarantees this because Node fires exactly one `close` or `error` event for each child process, never both.
- **Do not use `EffectFn` callbacks for the `onEvent` parameter** — it should be a regular PureScript function (`SpawnEvent -> Effect Unit`). The JS side calls it as a regular function (1 argument), which matches PureScript's default calling convention. Only the top-level `spawnImpl` needs `EffectFn4` to avoid curried wrapper overhead.

### String handling

- PureScript `String` is UTF-16 in JS runtime. Buffer chunks from `child_process` arrive as `Buffer` and are converted via `.toString()` in the FFI layer, matching the TypeScript implementation.

### StreamCallback in Aff context

The `stream` function calls a `StreamCallback` (which is `Effect Unit`) from within an `Aff`. Use `liftEffect` to call the callback when data arrives.

## 10. Parity Gaps to Watch For

### Must have (contract requirements)

| Gap | Risk | Mitigation |
|-----|------|------------|
| Error format exact match | High — contract test checks for `"failed to start"` substring | Mirror the C/TS error string format exactly in FFI layer |
| Exit code forwarding | High — `process.exit()` is required, not `return` | Use `Node.Process.exit` |
| Trailing newline on errors | Medium — C and Python include `\n` | Explicitly append `"\n"` in error messages |
| `CCC_REAL_OPENCODE` env override | High — contract tests depend on it | Read env var before building argv |

### Nice to have (feature parity)

| Gap | Notes |
|-----|-------|
| `Runner.stream` true streaming | The FFI naturally supports per-chunk callbacks. The `stream` function calls `liftEffect $ onEvent "stdout" chunk` on each data event, then returns the full `CompletedRun` at close. This matches TypeScript's behavior. |
| `stdinText` support | Supported in all other implementations. The FFI writes to `child.stdin` before closing it. |
| `cwd` / `env` overrides | Straightforward via `spawn` options. |
| `CCC_RUNNER_PREFIX_JSON` | TypeScript supports this; other implementations don't. Omit for v1. |

### Known PureScript pitfalls

| Pitfall | Mitigation |
|---------|------------|
| FFI type mismatches causing runtime crashes | Use `Foreign`/`Data.Foreign` for validation if needed; keep FFI surface minimal |
| `Aff` not completing because callback never fires | Ensure the FFI always fires `close` or `error` (Node guarantees this for spawn) |
| Spago package set version drift | Pin a specific package set in `packages.dhall` |
| `process.exit()` killing pending writes | Flush stdout/stderr before calling exit (use `launchAff_` and await stream completion) |

## 11. Build Instructions

### Prerequisites

- Node.js >= 18
- [Spago](https://github.com/purescript/spago) >= 0.93.0 (install via `npm install -g spago`)
- [PureScript compiler](https://github.com/purescript/purescript) >= 0.15.0 (install via `npm install -g purescript` or `spago` handles it)

### Initial setup

```bash
cd purescript
spago init  # generates spago.dhall, packages.dhall, src/, test/
# Then overwrite generated files with the structure in Section 1
```

### Build

```bash
cd purescript
spago build
```

Output goes to `output/`. The CLI entrypoint is `output/Node/CallCodingClis/CCC/index.js`.

### Run CLI

```bash
node purescript/output/Node/CallCodingClis/CCC/index.js "Fix the failing tests"
```

### Run unit tests

```bash
cd purescript
spago test
```

### Run cross-language contract tests

```bash
# From repo root, after spago build:
cd purescript && spago build && cd ..
python3 -m pytest tests/test_ccc_contract.py -v
```

## 12. CI Notes

### GitHub Actions

Add a job to the existing CI (if any) or create `.github/workflows/purescript.yml`:

```yaml
name: PureScript
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm install -g purescript spago
      - run: cd purescript && spago build
      - run: cd purescript && spago test
      - run: python3 -m pytest tests/test_ccc_contract.py -v -k "cross_language"
    # Note: cross-language contract tests also need cargo, make (C).
    # Run them in a separate job or ensure all deps are installed.
```

### Caching

`output/` is gitignored but can be large. Cache `~/.spago` and `purescript/output/` across CI runs for faster builds.

## 13. `.gitignore`

```
output/
.node-spago/
node_modules/
.spago/
.purs*
cache/
```

## 14. Implementation Checklist

- [ ] `spago init` and configure `spago.dhall` dependencies
- [ ] `src/CallCodingClis/Types.purs` — types
- [ ] `src/CallCodingClis/PromptSpec.purs` — `buildPromptSpec`
- [ ] `src/FFI/Spawn.purs` + `src/FFI/Spawn.js` — spawn FFI
- [ ] `src/CallCodingClis/Runner.purs` — `defaultRunner`, `runCommand`, `streamCommand`
- [ ] `src/CallCodingClis/CCC.purs` — CLI entrypoint with `CCC_REAL_OPENCODE`
- [ ] `package.json` — bin field
- [ ] `test/Main.purs` — unit tests
- [ ] `spago test` passes
- [ ] Add PureScript entries to `tests/test_ccc_contract.py` (4 test methods)
- [ ] `python3 -m pytest tests/test_ccc_contract.py -v` passes all 5 languages
- [ ] Update `IMPLEMENTATION_REFERENCE.md` — add PureScript row to feature parity matrix
- [ ] Update `CCC_BEHAVIOR_CONTRACT.md` — add PureScript section

