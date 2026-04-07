# VBScript Implementation Plan

## Overview

Implement the call-coding-clis library API and `ccc` CLI in VBScript for Windows Script Host (WSH/CScript). VBScript is Windows-only, interpreted, and has significant limitations compared to the Python/Rust/TypeScript/C reference implementations. This plan maps every contract requirement to VBScript idioms and identifies parity gaps.

---

## 1. File Structure

```
vbscript/
  runner.vbs        -- Library: CommandSpec, CompletedRun, Runner, BuildPromptSpec
  ccc.vbs           -- CLI entry point: ccc "<Prompt>"
  test_ccc.vbs      -- Self-test runner (uses CScript echo, not unittest)
  PLAN.md           -- This file
```

All files are standalone `.vbs` — no modules, no imports. `ccc.vbs` and `test_ccc.vbs` include `runner.vbs` at runtime via `ExecuteGlobal` (see section 9.7).

---

## 2. Library API

VBScript has no classes with constructors that accept parameters cleanly, and no dataclasses. Use factory functions and dictionary-based "structs" instead.

### 2.1 CommandSpec

```vbscript
Function MakeCommandSpec(argv, stdin_text, cwd, env)
  Set d = CreateObject("Scripting.Dictionary")
  Set d("argv") = argv          ' Array of strings
  d("stdin_text") = stdin_text  ' String or Empty
  d("cwd") = cwd                ' String or Empty
  Set d("env") = env            ' Scripting.Dictionary or Nothing
  Set MakeCommandSpec = d
End Function
```

- `argv`: VBScript array of strings (zero-based, from `Split` or manual `Array()`)
- `stdin_text`: `Empty` or string
- `cwd`: `Empty` or string
- `env`: `Nothing` or `Scripting.Dictionary`

### 2.2 CompletedRun

```vbscript
Function MakeCompletedRun(argv, exit_code, stdout_text, stderr_text)
  Set d = CreateObject("Scripting.Dictionary")
  Set d("argv") = argv
  d("exit_code") = exit_code    ' Integer
  d("stdout") = stdout_text     ' String
  d("stderr") = stderr_text     ' String
  Set MakeCompletedRun = d
End Function
```

### 2.3 Runner

```vbscript
Function MakeRunner()
  Set d = CreateObject("Scripting.Dictionary")
  d("type") = "Runner"
  Set MakeRunner = d
End Function

Function RunnerRun(runner, spec)
  ' Uses WScript.Shell.Exec to run spec("argv")
  ' Returns CompletedRun dictionary
End Function
```

- `RunnerRun(runner, spec) -> CompletedRun` — primary entry
- No `RunnerStream` — VBScript has no async I/O, no callback mechanism. See parity gaps (section 10).

### 2.4 BuildPromptSpec

```vbscript
Function BuildPromptSpec(prompt)
  trimmed = Trim(prompt)
  If Len(trimmed) = 0 Then
    Err.Raise vbObjectError + 1, "BuildPromptSpec", "prompt must not be empty"
  End If
  runner = GetOpencodeBinary()
  argv = Array(runner, "run", trimmed)
  Set BuildPromptSpec = MakeCommandSpec(argv, Empty, Empty, Nothing)
End Function

Function GetOpencodeBinary()
  Set shell = CreateObject("WScript.Shell")
  GetOpencodeBinary = shell.ExpandEnvironmentStrings("%CCC_REAL_OPENCODE%")
  If GetOpencodeBinary = "%CCC_REAL_OPENCODE%" Then
    GetOpencodeBinary = "opencode"
  End If
End Function
```

- Uses VBScript's `Trim()` for whitespace removal
- Raises error on empty/whitespace-only input (consistent with Python's `ValueError`)
- `GetOpencodeBinary()` reads `CCC_REAL_OPENCODE` env var via `ExpandEnvironmentStrings`; falls back to `"opencode"` if unset. `ExpandEnvironmentStrings` returns the literal `%VAR%` when the var doesn't exist, so we detect that.

---

## 3. Subprocess Execution via WScript.Shell

### 3.1 Primary method: `WScript.Shell.Exec`

`Exec` returns an object with `.StdOut`, `.StdErr`, `.StdIn` streams. It is synchronous when you call `.ReadAll` on the streams.

```vbscript
Function RunnerRun(runner, spec)
  Set shell = CreateObject("WScript.Shell")

  If Not IsEmpty(spec("cwd")) And Not IsNull(spec("cwd")) Then
    If Len(spec("cwd")) > 0 Then
      old_cwd = shell.CurrentDirectory
      shell.CurrentDirectory = spec("cwd")
    End If
  End If

  cmd = JoinCommandLine(spec("argv"))
  On Error Resume Next
  Set exec = shell.Exec(cmd)
  If Err.Number <> 0 Then
    stderr_msg = "failed to start " & spec("argv")(0) & ": " & Err.Description & vbCrLf
    On Error GoTo 0
    If Not IsEmpty(old_cwd) Then shell.CurrentDirectory = old_cwd
    Set RunnerRun = MakeCompletedRun(spec("argv"), 1, "", stderr_msg)
    Exit Function
  End If
  On Error GoTo 0

  If Not IsEmpty(spec("stdin_text")) And Not IsNull(spec("stdin_text")) Then
    exec.StdIn.Write spec("stdin_text")
    exec.StdIn.Close
  End If

  Do While exec.Status = 0
    WScript.Sleep 50
  Loop

  stdout_text = exec.StdOut.ReadAll
  stderr_text = exec.StdErr.ReadAll

  If Not IsEmpty(old_cwd) Then shell.CurrentDirectory = old_cwd

  Set RunnerRun = MakeCompletedRun(spec("argv"), exec.ExitCode, stdout_text, stderr_text)
End Function
```

Key behaviors:
- `Exec` requires the command as a single string (shell-parsed), not an argv array. Need `JoinCommandLine` to build a properly quoted command string.
- `ExitCode` is available after the process terminates.
- **Streams are read AFTER the process exits** (drain loop then `.ReadAll`). Reading before the loop risks deadlock if the child's stdout buffer fills while stderr is also filling. Post-exit reads are safe because the OS has already closed the child's pipe handles.
- CWD is saved/restored around the `Exec` call via `shell.CurrentDirectory`.
- Stdin is written and closed before the drain loop.

### 3.2 Command line joining

VBScript's `Exec` passes through `cmd.exe`, so arguments must be shell-escaped. Simple quoting heuristic:

```vbscript
Function JoinCommandLine(argv)
  parts = ""
  For i = 0 To UBound(argv)
    part = argv(i)
    part = Replace(part, """", "\""")
    part = """" & part & """"
    parts = parts & " " & part
  Next
  JoinCommandLine = Mid(parts, 2)
End Function
```

**Always quote every argument** rather than quoting only when spaces are detected. This avoids `cmd.exe` misinterpretation of special characters (`&`, `|`, `>`, `<`, `^`, `%`) in unquoted args. The escaping is not perfect for all edge cases (nested quotes, `%` expansion), but covers the common case of prompt strings passed to `opencode run`.

### 3.3 CWD and env

- **CWD**: `shell.CurrentDirectory` can be set before `Exec`, or use `shell.Run` with a working directory parameter (but `Run` doesn't capture stdout/stderr).
- **Approach**: Save and restore `shell.CurrentDirectory` around the `Exec` call if `spec("cwd")` is provided.
- **Env**: No way to pass custom environment to `Exec` directly. Would need to set env vars via `shell.Environment("Process")` before exec and restore after. This is racy in concurrent scenarios but VBScript is single-threaded.

### 3.4 Fallback: `WScript.Shell.Run`

`Run` is simpler but only provides exit code — no stdout/stderr capture. Useful only for the CLI case where output is already forwarded to the terminal (the process inherits handles). Not suitable for `Runner.run` which must capture output.

For the CLI (ccc.vbs), `Run` could be used for true output forwarding:

```vbscript
exit_code = shell.Run(cmd, 1, True)  ' 1=normal window, True=wait
WScript.Quit exit_code
```

This would give perfect output forwarding but no `CompletedRun` object.

---

## 4. ccc CLI (`ccc.vbs`)

```vbscript
' ccc.vbs -- entry point for "cscript ccc.vbs <Prompt>"
' Uses: cscript //nologo ccc.vbs "Fix the failing tests"

Set fso = CreateObject("Scripting.FileSystemObject")
Set lib_file = fso.OpenTextFile(fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "runner.vbs"))
ExecuteGlobal lib_file.ReadAll
lib_file.Close

Set args = WScript.Arguments.Unnamed
If args.Count <> 1 Then
  WScript.StdErr.WriteLine "usage: ccc ""<Prompt>"""
  WScript.Quit 1
End If

prompt = args(0)

On Error Resume Next
Set spec = BuildPromptSpec(prompt)
If Err.Number <> 0 Then
  WScript.StdErr.WriteLine Err.Description
  WScript.Quit 1
End If
On Error GoTo 0

Set runner = MakeRunner()
Set result = RunnerRun(runner, spec)

If result("stdout") <> "" Then WScript.StdOut.Write result("stdout")
If result("stderr") <> "" Then WScript.StdErr.Write result("stderr")

WScript.Quit result("exit_code")
```

### Invocation

```
cscript //nologo vbscript\ccc.vbs "Fix the failing tests"
set CCC_REAL_OPENCODE=C:\path\to\opencode.exe && cscript //nologo vbscript\ccc.vbs "Fix the failing tests"
```

Users would typically alias `ccc` to `cscript //nologo <path>\ccc.vbs`.

### Behavior

- Exactly one unnamed argument required
- Usage message on wrong arg count, exit 1
- Prompt trimmed, empty rejected, exit 1
- Stdout/stderr forwarded, exit code forwarded via `WScript.Quit`
- `CCC_REAL_OPENCODE` env var overrides the opencode binary (resolved in `GetOpencodeBinary`, called by `BuildPromptSpec`)

---

## 5. Prompt Trimming and Empty Rejection

- `Trim()` removes leading/trailing spaces in VBScript
- After trimming, check `Len(trimmed) = 0`
- On empty: write error message to stderr, `WScript.Quit 1`

This is consistent with all other implementations.

---

## 6. Error Format

The contract requires: `"failed to start <argv[0]>: <error>"`

In `RunnerRun`, when `WScript.Shell.Exec` raises an error (e.g., binary not found):

```vbscript
stderr_msg = "failed to start " & spec("argv")(0) & ": " & Err.Description & vbCrLf
```

Note: `Err.Description` may differ from Python's `str(error)` or Rust's error message, but the format prefix is consistent.

---

## 7. Exit Code Forwarding

- `WScript.Shell.Exec` returns an object with `.ExitCode` property (integer)
- CLI forwards via `WScript.Quit result("exit_code")`
- `WScript.Quit` accepts integers 0–255; values outside this range may be truncated

---

## 8. Test Strategy

VBScript has no test frameworks. Testing is done through:

### 8.1 Self-test script (`test_ccc.vbs`)

A VBScript script that exercises the library functions directly and reports pass/fail via `WScript.Echo`:

```vbscript
' test_ccc.vbs
Dim pass_count, fail_count
pass_count = 0
fail_count = 0

Sub Assert(condition, name)
  If condition Then
    WScript.Echo "  PASS: " & name
    pass_count = pass_count + 1
  Else
    WScript.Echo "  FAIL: " & name
    fail_count = fail_count + 1
  End If
End Sub

' --- BuildPromptSpec tests ---
On Error Resume Next
Set spec = BuildPromptSpec("  hello  ")
Assert Err.Number = 0, "BuildPromptSpec accepts padded prompt"
Assert spec("argv")(2) = "hello", "BuildPromptSpec trims prompt"
On Error GoTo 0

On Error Resume Next
Set spec = BuildPromptSpec("")
Assert Err.Number <> 0, "BuildPromptSpec rejects empty prompt"
On Error GoTo 0

On Error Resume Next
Set spec = BuildPromptSpec("   ")
Assert Err.Number <> 0, "BuildPromptSpec rejects whitespace-only prompt"
On Error GoTo 0

' --- CommandSpec structure ---
Set spec = BuildPromptSpec("test")
Assert spec("argv")(0) = "opencode", "argv[0] is opencode"
Assert spec("argv")(1) = "run", "argv[1] is run"
Assert spec("argv")(2) = "test", "argv[2] is trimmed prompt"
Assert IsEmpty(spec("stdin_text")), "stdin_text defaults to Empty"
Assert IsEmpty(spec("cwd")), "cwd defaults to Empty"

' --- CCC_REAL_OPENCODE ---
Set shell = CreateObject("WScript.Shell")
shell.Environment("Process")("CCC_REAL_OPENCODE") = "myopencode"
Set spec = BuildPromptSpec("test")
Assert spec("argv")(0) = "myopencode", "CCC_REAL_OPENCODE overrides binary"
shell.Environment("Process").Remove "CCC_REAL_OPENCODE"
Set spec = BuildPromptSpec("test")
Assert spec("argv")(0) = "opencode", "fallback to opencode when env unset"

' --- CompletedRun structure ---
Set run = MakeCompletedRun(Array("echo"), 0, "out", "err")
Assert run("exit_code") = 0, "CompletedRun exit_code"
Assert run("stdout") = "out", "CompletedRun stdout"
Assert run("stderr") = "err", "CompletedRun stderr"

' --- Summary ---
WScript.Echo pass_count & " passed, " & fail_count & " failed"
If fail_count > 0 Then WScript.Quit 1
```

Run with: `cscript //nologo vbscript/test_ccc.vbs`

### 8.2 Integration with cross-language contract tests

The existing `tests/test_ccc_contract.py` invokes CLIs as subprocesses. To include VBScript:

```python
# In test_ccc_contract.py, add:
subprocess.run(
    ["cscript", "//nologo", str(ROOT / "vbscript" / "ccc.vbs"), PROMPT],
    cwd=ROOT,
    env=env,
    capture_output=True,
    text=True,
    check=False,
)
```

This requires:
- Running on Windows (or WSL with `cscript` available)
- The `opencode` stub being a `.cmd` or `.bat` file for Windows

**Limitation**: Contract tests currently assume Unix. VBScript tests would only run on Windows CI or a Windows-specific test matrix.

### 8.3 Test stub for opencode on Windows

A `opencode.cmd` stub placed on PATH:

```cmd
@echo off
if "%~1"=="run" goto :run
exit /b 9
:run
echo opencode run %~2
```

---

## 9. VBScript-Specific Considerations

### 9.1 Windows-only, WSH environment

- VBScript runs under `cscript.exe` (console) or `wscript.exe` (GUI — avoid for CLI)
- Must use `cscript` explicitly; `wscript` would show message boxes instead of console output
- `WScript.StdOut`, `WScript.StdErr`, `WScript.StdIn` are only available under `cscript`

### 9.2 No streaming

- `WScript.Shell.Exec` provides `.StdOut` and `.StdErr` as text streams, but reading them blocks
- There is no async callback or event-based model in VBScript
- `RunnerStream` is not implementable. The `run` method will read all output after the process completes
- This matches the C implementation (no `stream` method) and the Rust non-streaming fallback

### 9.3 Limited error handling

- `On Error Resume Next` / `On Error GoTo 0` is the only error handling mechanism
- `Err.Number` and `Err.Description` for error details
- No try/catch/finally, no structured exception types
- Error information from `WScript.Shell.Exec` failures is limited to `Err.Description`

### 9.4 No array literals with mixed types cleanly

- `Array("opencode", "run", prompt)` works but arrays are zero-based `Variant()`
- `UBound` and `LBound` for bounds
- No list comprehensions, no map/filter

### 9.5 String handling

- `Trim()`, `LTrim()`, `RTrim()` for whitespace
- `Len()`, `Mid()`, `Replace()`, `InStr()`, `Split()`, `Join()`
- No regex in core VBScript (available via `VBScript.RegExp` COM object if needed)

### 9.6 Dictionary for structured data

- `CreateObject("Scripting.Dictionary")` is the closest thing to a dict/object
- Keys are case-sensitive by default (`.CompareMode = vbTextCompare` for case-insensitive)
- Used to simulate the CommandSpec/CompletedRun/Runner "classes"

### 9.7 Library loading via `ExecuteGlobal`

`ccc.vbs` and `test_ccc.vbs` load `runner.vbs` at startup using the calling script's directory (resolved via `WScript.ScriptFullName`), avoiding fragile relative paths:

```vbscript
Set fso = CreateObject("Scripting.FileSystemObject")
script_dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set lib_file = fso.OpenTextFile(fso.BuildPath(script_dir, "runner.vbs"))
ExecuteGlobal lib_file.ReadAll
lib_file.Close
```

**Decision**: Load via `ExecuteGlobal` using `ScriptFullName`-relative paths. This keeps library code in one place without duplication and works regardless of the caller's CWD.

---

## 10. Parity Gaps

| Feature | Python | Rust | TypeScript | C | **VBScript** |
|---|---|---|---|---|---|
| `BuildPromptSpec` | yes | yes | yes | yes | **yes** |
| `Runner.run` | yes | yes | yes | yes | **yes** |
| `Runner.stream` | yes | non-streaming fallback | yes | **no** | **no** |
| `ccc` CLI | yes | yes | yes | yes | **yes** |
| Prompt trimming | yes | yes | yes | yes | **yes** |
| Empty prompt rejection | yes | yes | yes | yes | **yes** |
| Stdin support | yes | yes | yes | yes | **yes** (via Exec.StdIn.Write) |
| CWD support | yes | yes | yes | yes | **yes** (via CurrentDirectory) |
| Env support | yes | yes | yes | yes | **partial** (set/process scope, racy) |
| Startup failure reporting | yes | yes | yes | yes | **yes** |
| Exit code forwarding | yes | yes | yes | yes | **yes** (0–255 range) |
| Cross-language tests | yes | yes | yes | yes | **no** (Windows-only) |
| `CCC_REAL_OPENCODE` | yes | yes | yes | yes | **yes** (`ExpandEnvironmentStrings`) |

### Notable gaps

1. **No streaming** — VBScript has no async I/O. `RunnerStream` is omitted entirely. Same as the C implementation.

2. **Env override is process-scoped and racy** — Must mutate the process environment via `WScript.Shell.Environment("Process")` before exec. Not safe if concurrent processes are running. No equivalent of `subprocess.run(env=override)`.

3. **Windows-only** — Cannot run on Linux/macOS. Cannot participate in the cross-language contract tests (which assume Unix shells). Needs a separate Windows CI pipeline.

4. **`Exec` goes through `cmd.exe`** — Arguments are shell-parsed, unlike Python/Rust/C which pass argv directly. This creates quoting/escaping differences for prompts containing special shell characters (`&`, `|`, `>`, `<`, `^`, `%`).

5. **No native unittest** — Test assertions are hand-rolled. No discovery, no fixtures, no reporting framework.

6. **Exit code range** — `WScript.Quit` may truncate to 8-bit unsigned. The existing contract tests use exit code 0 and 1, which are safe.

7. **No C implementation of `stream`** — VBScript matches C's parity here. Not a regression.

---

## 11. Implementation Order

1. `runner.vbs` — CommandSpec, CompletedRun, MakeRunner, RunnerRun, BuildPromptSpec, JoinCommandLine
2. `ccc.vbs` — CLI entry point, arg validation, output forwarding, exit code
3. `test_ccc.vbs` — Unit-level tests for library functions
4. Integration: add VBScript entries to cross-language contract tests (Windows CI only)
5. Windows opencode stub for testing

---

## 12. Build and Test Instructions

No build step required — VBScript is interpreted. Prerequisites: Windows with `cscript.exe` (ships with all modern Windows).

### Unit tests (library functions)

```cmd
cscript //nologo vbscript\test_ccc.vbs
```

Exits 0 on all pass, 1 on first failure. Output is `PASS: <name>` / `FAIL: <name>` lines.

### CLI smoke test (requires `opencode` on PATH or `CCC_REAL_OPENCODE` set)

```cmd
cscript //nologo vbscript\ccc.vbs "hello"
echo %ERRORLEVEL%
```

### CLI with test stub

```cmd
rem Place opencode.cmd in a temp dir on PATH
set PATH=C:\tmp\bin;%PATH%
set CCC_REAL_OPENCODE=C:\tmp\bin\opencode.cmd
cscript //nologo vbscript\ccc.vbs "Fix the failing tests"
```

---

## 13. Cross-Language Test Registration

`tests/test_ccc_contract.py` uses hardcoded inline `subprocess.run` calls per language. To add VBScript, append a new block to each test method:

```python
self.assert_equal_output(
    subprocess.run(
        ["cscript", "//nologo", str(ROOT / "vbscript" / "ccc.vbs"), PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

Requirements for this to work:
- **Windows runner** — `cscript` is not available on Unix
- **Windows `opencode` stub** — the existing `_write_opencode_stub` writes a shell script (`.sh`). VBScript tests need a separate `_write_opencode_stub_cmd` helper that writes a `.cmd` file. Example:

```python
def _write_opencode_stub_cmd(self, path: Path) -> None:
    path.write_text(
        "@echo off\r\n"
        'if "%~1"=="run" goto :run\r\n'
        "exit /b 9\r\n"
        ":run\r\n"
        "echo opencode run %~2\r\n"
    )
```

- **Guard** — wrap the VBScript block in a platform check so Unix CI doesn't fail:

```python
import platform
if platform.system() == "Windows":
    # ... VBScript subprocess.run block ...
```

Or gate it behind an environment variable: `if os.environ.get("CCC_TEST_VBSCRIPT"):`.

---

## 14. CI Notes

No CI pipeline exists in this repository today (no `.github/workflows/`, no `Makefile` at root). When CI is added:

- **VBScript tests must run in a `windows-latest` runner only.** `cscript` is unavailable on Linux/macOS.
- **Separate job or matrix entry** — add a `windows-latest` job that runs `cscript //nologo vbscript\test_ccc.vbs` and optionally the cross-language contract tests with the VBScript registration block enabled.
- **No build step** — VBScript is interpreted, so there is nothing to compile or install.
- **Minimal dependencies** — only `cscript.exe` (pre-installed) and `opencode` (mocked via stub).
