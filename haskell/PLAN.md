# Haskell Implementation Plan

## 1. Project Structure (Cabal)

Single `haskell/` directory with a Cabal package. No Stack — Cabal alone is simpler and consistent with the other language implementations that use their standard toolchains. No hpack — hand-written `.cabal` avoids the ambiguity of "which is source of truth?" and keeps the build fully explicit.

```
haskell/
  ccc.cabal
  cabal.project
  src/
    CallCodingClis/
      Runner.hs
    ccc.hs
  test/
    Main.hs
```

The `.cabal` file defines:

- Library `call-coding-clis` exposing `CallCodingClis.Runner`
- Executable `ccc` with `main-is: ccc.hs`
- Test suite `ccc-test` using Hspec, `main-is: test/Main.hs`, `type: exitcode-stdio-1.0`

### ccc.cabal

```cabal
cabal-version:      3.0
name:               ccc
version:            0.1.0.0
build-type:         Simple
license:            Unlicense

library
  exposed-modules:    CallCodingClis.Runner
  build-depends:      base >= 4.18 && < 5
                    , process >= 1.6
                    , text >= 2.0
  hs-source-dirs:     src
  default-language:   GHC2021
  ghc-options:        -Wall -Werror

executable ccc
  main-is:            ccc.hs
  build-depends:      base >= 4.18 && < 5
                    , process >= 1.6
                    , ccc
  hs-source-dirs:     src
  default-language:   GHC2021
  ghc-options:        -Wall -Werror

test-suite ccc-test
  main-is:            Main.hs
  build-depends:      base >= 4.18 && < 5
                    , process >= 1.6
                    , text >= 2.0
                    , hspec >= 2.11
                    , ccc
  hs-source-dirs:     test
  default-language:   GHC2021
  ghc-options:        -Wall -Werror -threaded -rtsopts -with-rtsopts=-N
```

### cabal.project

```cabal
store-dir: dist-newstyle/store
```

Requires GHC >= 9.6 (for GHC2021, `do`-notation in `ApplicativeDo` / hspec-2.11+).

## 2. Build Instructions

```bash
# Build library + executable + tests
cd haskell && cabal build all

# Run the CLI
cabal run ccc -- "Fix the failing tests"

# Run Haskell-internal tests
cabal test ccc-test

# Build only (for contract test harness)
cabal build ccc
```

### Prerequisites

- GHC >= 9.6 and cabal-install >= 3.10
- No other external dependencies — `process` and `text` ship with GHC or are boot packages

### Discovering the built binary (for scripts)

```bash
cabal list-bin ccc
# e.g. ~/.cabal/store/ghc-9.6.4/ccc-0.1.0.0-x/bin/ccc
```

Use this instead of hardcoding `dist-newstyle/` paths, which vary by GHC version and platform.

## 3. Library API

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
  , csEnv       :: [(String, String)]
  }
  deriving (Eq, Show)
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
  deriving (Eq, Show)
```

Uses Haskell's `System.Exit.ExitCode` (`ExitSuccess` | `ExitFailure Int`). The contract tests check returncode semantics, and `ExitCode` maps 1:1. The CLI converts to an OS exit code via `exitWith`.

### Runner

```haskell
type StreamCallback = String -> String -> IO ()

data Runner = Runner
  { runnerRun    :: CommandSpec -> IO CompletedRun
  , runnerStream :: CommandSpec -> StreamCallback -> IO CompletedRun
  }

defaultRunner :: Runner
defaultRunner = Runner defaultRunExecutor defaultStreamExecutor
```

The record-of-functions pattern avoids type classes for injectability — matches Rust's boxed executor pattern. Supply a custom `Runner` with stub functions for testing.

### buildPromptSpec

```haskell
buildPromptSpec :: String -> Either String CommandSpec
buildPromptSpec prompt =
  let trimmed = strip prompt
  in if null trimmed
       then Left "prompt must not be empty"
       else Right $ CommandSpec ["opencode", "run", trimmed] Nothing Nothing []
```

`strip` from `Data.Text` for correct Unicode whitespace handling. Returns `Either` instead of throwing, consistent with Rust's `Result`.

## 4. Subprocess via System.Process

### Why `readCreateProcessWithExitCode`, not `readProcessWithExitCode`

`readProcessWithExitCode` has signature:
```haskell
readProcessWithExitCode :: FilePath -> String -> [String] -> String
                        -> IO (ExitCode, String, String)
```
The first argument is the **command path**, not cwd. It does NOT support setting `cwd` or custom `env`. To get full `CommandSpec` support (cwd, env overrides, stdin), use `readCreateProcessWithExitCode` which accepts a `CreateProcess` record.

### Run Executor

```haskell
import System.Process hiding (env)
import System.Exit (ExitCode(..))
import System.IO.Error (tryIOError, ioeGetErrorType, isDoesNotExistErrorType)
import Control.Exception (displayException)

defaultRunExecutor :: CommandSpec -> IO CompletedRun
defaultRunExecutor spec
  | null (csArgv spec) = pure $ CompletedRun [] (ExitFailure 1) ""
      "failed to start (unknown): argv is empty\n"
  | otherwise = do
      let (cmd : args) = csArgv spec
          procSpec = (proc cmd args)
            { cwd = csCwd spec
            , env = envWithOverrides (csEnv spec)
            , std_in = case csStdinText spec of
                Just _  -> CreatePipe
                Nothing -> Inherit
            , std_out = CreatePipe
            , std_err = CreatePipe
            }
      result <- tryIOError $ readCreateProcessWithExitCode procSpec
                   (fromMaybe "" (csStdinText spec))
      case result of
        Left err -> pure $ CompletedRun (csArgv spec) (ExitFailure 1) ""
          ("failed to start " ++ cmd ++ ": " ++ displayException err ++ "\n")
        Right (exitCode, out, err') -> pure $ CompletedRun (csArgv spec) exitCode out err'
```

Key differences from the naive approach:

1. **Guard on empty argv** — `let (cmd:args) = csArgv spec` is a partial pattern; we check `null` first.
2. **`readCreateProcessWithExitCode`** — supports `cwd`, `env`, and `std_in` via `CreateProcess`.
3. **`displayException`** — produces human-readable messages (e.g., `"does not exist (No such file or directory)"`) instead of `show` which adds Haskell-internal formatting like `"user error (…\n)"`.
4. **`tryIOError`** — equivalent to `try @IOException` but avoids ScopedTypeVariables, keeping the code simpler.

### Env Merging Helper

```haskell
import System.Environment (getEnvironment)
import Data.Maybe (isNothing)

envWithOverrides :: [(String, String)] -> Maybe [(String, String)]
envWithOverrides []       = Nothing  -- inherit parent env
envWithOverrides overrides =
    Just . (++ overrides) <$> getEnvironment
```

When env overrides are empty, pass `Nothing` (inherit). Otherwise, merge current env with overrides, matching Python's `dict(os.environ); env.update(overrides)` pattern.

**Important**: This is an `IO` action. Call it inside `defaultRunExecutor` before constructing the `CreateProcess` record.

### Stream Executor (Non-Streaming, v1)

Matches Rust's current non-streaming stream — delegates to `run` and fires callbacks after completion:

```haskell
defaultStreamExecutor :: CommandSpec -> StreamCallback -> IO CompletedRun
defaultStreamExecutor spec callback = do
  result <- defaultRunExecutor spec
  unless (null $ crStdout result) $ callback "stdout" (crStdout result)
  unless (null $ crStderr result) $ callback "stderr" (crStderr result)
  pure result
```

True chunk-by-chunk streaming via `createProcess` + `ByteString` lazy I/O can be added later.

## 5. ccc CLI Executable

`src/ccc.hs`:

```haskell
module Main where

import System.Environment (getArgs, lookupEnv)
import System.Exit (exitWith, ExitCode(..))
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
          mOverride <- lookupEnv "CCC_REAL_OPENCODE"
          let spec' = case mOverride of
                Nothing  -> spec
                Just bin -> spec { csArgv = bin : tail (csArgv spec) }
          result <- runnerRun defaultRunner spec'
          putStr (crStdout result)
          hPutStr stderr (crStderr result)
          exitWith (crExitCode result)
    _ -> do
      hPutStrLn stderr "usage: ccc \"<Prompt>\""
      exitWith (ExitFailure 1)
```

### CCC_REAL_OPENCODE

The CLI reads `CCC_REAL_OPENCODE` and substitutes it for `argv[0]` in the spec, matching the C implementation's behavior exactly (`c/src/ccc.c:48-51`). This is done at the CLI layer, not in `buildPromptSpec`, keeping the library unaware of environment-specific overrides.

## 6. Prompt Trimming

```haskell
import qualified Data.Text as T

strip :: String -> String
strip = T.unpack . T.strip . T.pack
```

`Text.strip` handles Unicode whitespace correctly (unlike a naive `dropWhile isSpace` on `String`). After stripping, `null` (on the resulting `String`) rejects empty/whitespace-only prompts.

## 7. Error Format

On startup failure (binary not found, permission denied):

```
failed to start <argv[0]>: <error message>
```

Only `argv[0]`, not the full command line. Constructed in `defaultRunExecutor` when `readCreateProcessWithExitCode` throws `IOException`. Uses `displayException` for the error detail. The message ends with `\n`.

## 8. Exit Code Forwarding

Use `System.Exit.exitWith :: ExitCode -> IO a`:
- `ExitSuccess` -> code 0
- `ExitFailure Int` -> that int

The CLI calls `exitWith (crExitCode result)` directly — no wrapping.

## 9. Test Strategy

### Framework: Hspec

`test/Main.hs`:

```haskell
module Main where

import Test.Hspec
import System.Exit (ExitCode(..))
import CallCodingClis.Runner

main :: IO ()
main = hspec do
  describe "buildPromptSpec" do
    it "trims and builds spec" do
      buildPromptSpec "  hello  "
        `shouldBe` Right (CommandSpec ["opencode","run","hello"] Nothing Nothing [])

    it "rejects empty string" do
      buildPromptSpec "" `shouldBe` Left "prompt must not be empty"

    it "rejects whitespace-only" do
      buildPromptSpec "   \t  " `shouldBe` Left "prompt must not be empty"

    it "trims Unicode whitespace" do
      buildPromptSpec "\x2003hello\x2003"
        `shouldBe` Right (CommandSpec ["opencode","run","hello"] Nothing Nothing [])

  describe "defaultRunner" do
    it "captures output and exit code" do
      let spec = CommandSpec ["echo", "hello"] Nothing Nothing []
      result <- runnerRun defaultRunner spec
      crExitCode result `shouldBe` ExitSuccess
      crStdout result `shouldBe` "hello\n"
      crStderr result `shouldBe` ""

    it "captures stderr" do
      let spec = CommandSpec ["sh", "-c", "echo oops >&2"] Nothing Nothing []
      result <- runnerRun defaultRunner spec
      crExitCode result `shouldBe` ExitSuccess
      crStderr result `shouldBe` "oops\n"

    it "reports startup failure for nonexistent binary" do
      let spec = CommandSpec ["nonexistent_binary_xyz"] Nothing Nothing []
      result <- runnerRun defaultRunner spec
      crExitCode result `shouldBe` ExitFailure 1
      crStderr result `shouldContain` "failed to start nonexistent_binary_xyz"

    it "forwards nonzero exit code" do
      let spec = CommandSpec ["sh", "-c", "exit 42"] Nothing Nothing []
      result <- runnerRun defaultRunner spec
      crExitCode result `shouldBe` ExitFailure 42

    it "handles empty argv" do
      let spec = CommandSpec [] Nothing Nothing []
      result <- runnerRun defaultRunner spec
      crExitCode result `shouldBe` ExitFailure 1
      crStderr result `shouldContain` "failed to start"

  describe "stream (v1 non-streaming)" do
    it "fires stdout callback" do
      let spec = CommandSpec ["echo", "hi"] Nothing Nothing []
      ref <- newIORef ("" :: String)
      _ <- runnerStream defaultRunner spec $ \chan chunk ->
        modifyIORef' ref (++ chan ++ ":" ++ chunk)
      output <- readIORef ref
      output `shouldSatisfy` ("stdout" `isInfixOf`)
```

Imports needed for tests:
```haskell
import Data.IORef (newIORef, readIORef, modifyIORef')
import Data.List (isInfixOf)
```

## 10. Cross-Language Contract Test Registration

Add Haskell blocks to each of the four test methods in `tests/test_ccc_contract.py`. Each block follows the pattern: build, then invoke.

### Build step (shared across tests)

Add a helper method to `CccContractTests`:

```python
def _build_haskell_ccc(self, env) -> None:
    subprocess.run(
        ["cabal", "build", "ccc"],
        cwd=str(ROOT / "haskell"),
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
```

### Per-test additions

In `test_cross_language_ccc_happy_path`, after the C block:

```python
self._build_haskell_ccc(env)
self.assert_equal_output(
    subprocess.run(
        ["cabal", "run", "ccc", "--", PROMPT],
        cwd=str(ROOT / "haskell"),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

Repeat the same pattern for `test_cross_language_ccc_rejects_empty_prompt` (with `""`), `test_cross_language_ccc_requires_one_prompt_argument` (no args), and `test_cross_language_ccc_rejects_whitespace_only_prompt` (with `"   "`), adjusting `assert_rejects_empty` / `assert_rejects_missing_prompt` accordingly.

**Note**: `cabal run` rebuilds only if stale, so the build overhead is minimal on repeated test invocations within the same session. Alternatively, use `cabal list-bin ccc` to discover the binary path once and invoke it directly (avoiding cabal startup overhead), at the cost of an extra subprocess call.

## 11. Haskell-Specific Considerations

### Monadic IO
All subprocess work is in `IO`. The `Runner` type uses `IO` in its function slots. No need for monad transformers — the operations are simple and don't compose with other effects.

### Strict I/O
`readCreateProcessWithExitCode` collects all output strictly into `String`s, so no lazy-IO pitfalls. If true streaming is added later with `createProcess` + `hGetContents`, consume handles fully before `waitForProcess`, or use `ByteString` strict reads.

### Strong Typing
- `ExitCode` prevents mixing up success/failure with raw ints
- `Either String CommandSpec` makes the empty-prompt rejection path explicit
- `Eq`/`Show` derived on `CommandSpec` and `CompletedRun` enable Hspec assertions

### String vs Text vs ByteString
- Public API uses `String` for simplicity and consistency with `System.Process`
- Internal trimming uses `Data.Text` for correctness
- Streaming (future) would use `ByteString` internally

### No Dependency Bloat
Only `process` and `text` — both boot packages or very common. No `async`, `conduit`, `pipes`, etc.

## 12. CI Notes

### GHC / Cabal Installation

GitHub Actions example:

```yaml
- uses: haskell-actions/setup@v2
  with:
    ghc-version: '9.10'
    cabal-version: '3.12'
```

### Build + Test Step

```yaml
- name: Haskell build
  working-directory: haskell
  run: cabal build all

- name: Haskell tests
  working-directory: haskell
  run: cabal test ccc-test
```

### Contract Tests

The contract test harness (`tests/test_ccc_contract.py`) already invokes each implementation as a subprocess. Ensure GHC and cabal are on `$PATH` in the CI runner.

Add `haskell/dist-newstyle` and `haskell/.cabal-sandbox` to `.gitignore`.

### Caching

```yaml
- uses: actions/cache@v4
  with:
    path: |
      ~/.cabal/store
      haskell/dist-newstyle
    key: haskell-${{ runner.os }}-ghc-9.10-${{ hashFiles('haskell/**/*.cabal') }}
    restore-keys: haskell-${{ runner.os }}-ghc-9.10-
```

## 13. Parity Gaps to Watch For

| Concern | Detail |
|---------|--------|
| `CCC_REAL_OPENCODE` in CLI | Handled in `ccc.hs` via `lookupEnv`, matching C's behavior. The library is unaware of it. |
| Streaming | v1 delegates to `run` + post-hoc callbacks, matching Rust. True chunk-by-chunk streaming via `createProcess` + `ByteString` can be added later. |
| Env merging | `envWithOverrides` merges `getEnvironment` with overrides when non-empty; passes `Nothing` (inherit) otherwise. Matches Python's `dict(os.environ); env.update(overrides)`. |
| Build reproducibility | `cabal build` produces binaries at GHC-version-dependent paths. Contract tests use `cabal run` (or `cabal list-bin` for direct invocation). |
| Signal handling | If the child is killed by a signal, `readCreateProcessWithExitCode` returns `ExitFailure` with a platform-specific code, which is forwarded as-is. Matches the contract. |
| Exit code 1 on startup failure | C's child uses `_exit(127)` on exec failure, but C's library wraps the result. Haskell catches `IOException` before exec and returns `ExitFailure 1`, matching the contract's expectation of exit code 1 on startup failure. |
| Contract test integration | Haskell blocks must be added to all four test methods in `tests/test_ccc_contract.py`. See Section 10. |
| Empty argv guard | `defaultRunExecutor` guards against empty argv with a descriptive error, avoiding a partial-pattern crash. |
| `displayException` vs `show` | Uses `displayException` for human-readable error messages; `show` would produce Haskell-internal formatting like `"does not exist"` vs `"user error (does not exist\n)"`. |
