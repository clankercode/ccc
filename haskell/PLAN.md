# Haskell Implementation Plan

## 1. Project Structure (Cabal)

Single `haskell/` directory with a Cabal package. No Stack — Cabal alone is simpler and consistent with the other language implementations that use their standard toolchains.

```
haskell/
  ccc.cabal
  package.yaml          # hpack optional, but .cabal is primary
  src/
    lib/
      CallCodingClis/
        Runner.hs        # CommandSpec, CompletedRun, Runner, buildPromptSpec
        Cli.hs           # ccc CLI main
    ccc.hs               # executable entrypoint
  test/
    Spec.hs              # Hspec test suite
```

The `.cabal` file defines:

- Library `call-coding-clis` exposing `CallCodingClis.Runner` and `CallCodingClis.Cli`
- Executable `ccc` with `main-is: ccc.hs`
- Test suite `ccc-test` using Hspec

Dependencies (GHC ≥ 9.6, base ≥ 4.18):
- `process` (System.Process — ships with GHC)
- `text` (Data.Text — for strict, correct trimming)
- `bytestring` (for process IO)
- `hspec` (test only)

The contract tests in `tests/test_ccc_contract.py` will need a new block added that invokes `cabal run ccc -- "<prompt>"` from `haskell/`. The Haskell binary path is `haskell/dist-newstyle/.../build/ccc/ccc` or invoked via `cabal run`.

## 2. Library API

```haskell
module CallCodingClis.Runner
  ( CommandSpec(..)
  , CompletedRun(..)
  , Runner(..)
  , buildPromptSpec
  , StreamCallback
  ) where
```

### CommandSpec

```haskell
data CommandSpec = CommandSpec
  { csArgv      :: [String]
  , csStdinText :: Maybe String
  , csCwd       :: Maybe FilePath
  , csEnv       :: [(String, String)]  -- override entries only
  }
```

Matches the other implementations: argv list, optional stdin, optional cwd, env overrides.

### CompletedRun

```haskell
data CompletedRun = CompletedRun
  { crArgv     :: [String]
  , crExitCode :: ExitCode
  , crStdout   :: String
  , crStderr   :: String
  }
```

Uses Haskell's `System.Exit.ExitCode` (`ExitSuccess` | `ExitFailure Int`) instead of a raw int. The contract tests check returncode semantics, and `ExitCode` maps 1:1. When constructing `CompletedRun` from `readProcessWithExitCode`, the `ExitCode` is used directly. The CLI converts it to an OS exit code via `exitWith`.

### Runner

```haskell
type StreamCallback = String -> String -> IO ()  -- channel, chunk

data Runner = Runner
  { runnerRun    :: CommandSpec -> IO CompletedRun
  , runnerStream :: CommandSpec -> StreamCallback -> IO CompletedRun
  }

defaultRunner :: Runner
defaultRunner = Runner defaultRunExecutor defaultStreamExecutor
```

The record-of-functions pattern avoids type classes for injectability — matches Rust's boxed executor pattern. For testing, supply a custom `Runner` that invokes a stub.

### buildPromptSpec

```haskell
buildPromptSpec :: String -> Either String CommandSpec
buildPromptSpec prompt =
  let trimmed = strip prompt
  in if null trimmed
       then Left "prompt must not be empty"
       else Right $ CommandSpec ["opencode", "run", trimmed] Nothing Nothing []
```

`strip` from `Data.Text` (via `Data.Text.strip . pack`, then `unpack`) or the simpler `Data.List.dropWhileEnd` approach. Returns `Either` instead of throwing, consistent with Rust's `Result` and giving the CLI control over error messages.

## 3. Subprocess via System.Process

Use `System.Process.readProcessWithExitCode` for the `run` path:

```haskell
defaultRunExecutor :: CommandSpec -> IO CompletedRun
defaultRunExecutor spec = do
  let (cmd:args) = csArgv spec
  env <- case csEnv spec of
    [] -> Nothing          -- inherit
    overrides -> Just . (++ overrides) <$> getEnvironment
  result <- try (readProcessWithExitCode (csCwd spec) cmd args (csStdinText spec)) :: IO (Either IOException (ExitCode, String, String))
  case result of
    Left err -> return $ CompletedRun (csArgv spec) (ExitFailure 1) ""
                    ("failed to start " ++ cmd ++ ": " ++ show err ++ "\n")
    Right (exitCode, out, err') -> return $ CompletedRun (csArgv spec) exitCode out err'
```

For the `stream` path, use `createProcess` with `CreateProcess` record, piping stdout/stderr, and reading in chunks. Alternatively, for v1 parity with Rust's non-streaming stream, just delegate to `run` and fire callbacks after:

```haskell
defaultStreamExecutor :: CommandSpec -> StreamCallback -> IO CompletedRun
defaultStreamExecutor spec callback = do
  result <- defaultRunExecutor spec
  unless (null $ crStdout result) $ callback "stdout" (crStdout result)
  unless (null $ crStderr result) $ callback "stderr" (crStderr result)
  return result
```

This matches Rust's current non-streaming stream behavior exactly. True streaming can be added later via `createProcess` + lazy ByteI/O.

## 4. ccc CLI Executable

`src/ccc.hs`:

```haskell
module Main where

import System.Environment (getArgs)
import System.Exit (exitWith)
import System.IO (hPutStrLn, stderr)
import CallCodingClis.Runner (buildPromptSpec, defaultRunner, CompletedRun(..))

main :: IO ()
main = do
  args <- getArgs
  case args of
    [prompt] -> do
      case buildPromptSpec prompt of
        Left err -> hPutStrLn stderr err >> exitWith (ExitFailure 1)
        Right spec -> do
          result <- runnerRun defaultRunner spec
          putStr (crStdout result)
          hPutStr stderr (crStderr result)
          exitWith (crExitCode result)
    _ -> do
      hPutStrLn stderr "usage: ccc \"<Prompt>\""
      exitWith (ExitFailure 1)
```

`CCC_REAL_OPENCODE` is handled by the contract test harness setting PATH, not by the library itself. If needed for direct testing, it can be plumbed into the CLI via `System.Environment.getEnv` to override the first argv element before building the spec.

## 5. Prompt Trimming

Use `Data.Text`:

```haskell
import qualified Data.Text as T

strip :: String -> String
strip = T.unpack . T.strip . T.pack
```

`Text.strip` handles Unicode whitespace correctly (unlike a naive `dropWhile isSpace` on `String`). After stripping, check `Data.Text.null` to reject empty/whitespace-only prompts.

## 6. Error Format

On startup failure (binary not found, permission denied):

```
failed to start <argv[0]>: <error message>
```

Only `argv[0]`, not the full command line. This is constructed in `defaultRunExecutor` when catching `IOException` from `readProcessWithExitCode`. The error message ends with `\n`.

## 7. Exit Code Forwarding

Use `System.Exit.exitWith :: ExitCode -> IO a`. This exits the process with the exact code from the child. `ExitCode` from `System.Exit` is:
- `ExitSuccess` → code 0
- `ExitFailure Int` → that int

The CLI calls `exitWith (crExitCode result)` directly — no wrapping.

## 8. Test Strategy

### Framework: Hspec

```haskell
module Spec where

import Test.Hspec
import CallCodingClis.Runner

main :: IO ()
main = hspec do
  describe "buildPromptSpec" do
    it "trims and builds spec" do
      buildPromptSpec "  hello  " `shouldBe` Right (CommandSpec ["opencode","run","hello"] Nothing Nothing [])

    it "rejects empty string" do
      buildPromptSpec "" `shouldBe` Left "prompt must not be empty"

    it "rejects whitespace-only" do
      buildPromptSpec "   \t  " `shouldBe` Left "prompt must not be empty"

  describe "Runner" do
    it "captures output and exit code" do
      -- Use /bin/echo as a known-good subprocess
      let spec = CommandSpec ["echo", "hello"] Nothing Nothing []
      result <- runnerRun defaultRunner spec
      crExitCode result `shouldBe` ExitSuccess
      crStdout result `shouldBe` "hello\n"
```

### CCC_REAL_OPENCODE Override

For integration-level tests that run the actual `ccc` binary, the existing `tests/test_ccc_contract.py` contract tests invoke the CLI as a subprocess. A Haskell block is added:

```python
# Build once
subprocess.run(["cabal", "build", "--builddir=dist-newstyle"], cwd="haskell", check=True)

# Invoke
result = subprocess.run(
    ["cabal", "run", "--builddir=dist-newstyle", "ccc", "--", PROMPT],
    cwd="haskell",
    env=env,
    capture_output=True,
    text=True,
    check=False,
)
```

For Haskell-internal subprocess tests that need to point at a specific binary, read `CCC_REAL_OPENCODE` env var and substitute it for `"opencode"` in the spec's argv, matching the C implementation's approach.

## 9. Haskell-Specific Considerations

### Monadic IO
All subprocess work is in `IO`. The `Runner` type uses `IO` in its function slots. No need for monad transformers here — the operations are simple and don't compose with other effects.

### Lazy I/O Caution
`readProcessWithExitCode` from `System.Process` is strict about its String results (it collects the full output), so no lazy-IO pitfalls. If true streaming is added later with `createProcess` + `hGetContents`, use `ByteString` (strict or lazy) and consume fully before waiting, or use `System.IO.Strict` wrappers.

### Strong Typing
- `ExitCode` prevents mixing up success/failure with raw ints
- `Either String CommandSpec` makes the empty-prompt rejection path explicit
- `newtype` wrappers are not needed here — the types are small and the field accessors are clear. If the library grows, `newtype Argv = Argv [String]` could be added for type safety

### String vs Text vs ByteString
- Public API uses `String` for simplicity and consistency with `System.Process` which operates on `String`
- Internal trimming uses `Data.Text` for correctness
- If streaming is ever implemented at the byte level, `ByteString` would be used internally

### No Dependency Bloat
The library depends only on `process` and `text` (both very common). No need for `async`, `conduit`, `pipes`, `unliftio`, etc. for the current feature set.

## 10. Parity Gaps to Watch For

| Concern | Detail |
|---------|--------|
| `CCC_REAL_OPENCODE` in CLI | C implementation reads this env var directly in its CLI. The contract tests work around it by setting PATH. For consistency, add env var reading in the Haskell CLI to override argv[0], matching C's behavior. The library `buildPromptSpec` does not need to know about it. |
| Streaming | Currently all implementations except C's runner support streaming (though Rust's is non-streaming). The Haskell v1 should match Rust: `stream` exists but delegates to `run` + post-hoc callbacks. True chunk-by-chunk streaming via `createProcess` can be added later. |
| Env merging | Python merges `os.environ` with overrides. `readProcessWithExitCode` accepts `Maybe [(String,String)]` where `Nothing` inherits. The Haskell implementation should merge explicitly when env overrides are provided: `Just . (++ overrides) <$> getEnvironment`. |
| Build reproducibility | `cabal build` produces a binary at a path that depends on GHC version and platform. The contract test must use `cabal run` rather than hardcoding a path, or discover the binary via `cabal list-bin`. |
| Signal handling | If the child is killed by a signal, `readProcessWithExitCode` returns `ExitFailure` with a platform-specific code. This matches the contract — the exit code is forwarded as-is. |
| Exit code 127 vs 1 | C implementation's child uses `_exit(127)` on exec failure, but the C library wraps the result with its own error format. The Haskell implementation catches `IOException` before exec and returns `ExitFailure 1`, which matches the contract's expectation of exit code 1 on startup failure. |
| Contract test integration | The `tests/test_ccc_contract.py` file needs a Haskell block added for each test method. This is outside the Haskell code but required for full parity. |
