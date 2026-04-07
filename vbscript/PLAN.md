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

All files are standalone `.vbs` — no modules, no imports. The "library" is loaded via `ExecuteGlobal` or simple inclusion via a helper function.

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
  argv = Array("opencode", "run", trimmed)
  Set BuildPromptSpec = MakeCommandSpec(argv, Empty, Empty, Nothing)
End Function
```

- Uses VBScript's `Trim()` for whitespace removal
- Raises error on empty/whitespace-only input (consistent with Python's `ValueError`)

---

## 3. Subprocess Execution via WScript.Shell

### 3.1 Primary method: `WScript.Shell.Exec`

`Exec` returns an object with `.StdOut`, `.StdErr`, `.StdIn` streams. It is synchronous when you call `.ReadAll` on the streams.

```vbscript
Function RunnerRun(runner, spec)
  Set shell = CreateObject("WScript.Shell")
  cmd = JoinCommandLine(spec("argv"))
  On Error Resume Next
  Set exec = shell.Exec(cmd)
  If Err.Number <> 0 Then
    stderr_msg = "failed to start " & spec("argv")(0) & ": " & Err.Description & vbCrLf
    On Error GoTo 0
    Set RunnerRun = MakeCompletedRun(spec("argv"), 1, "", stderr_msg)
    Exit Function
  End If
  On Error GoTo 0

  stdout_text = exec.StdOut.ReadAll
  stderr_text = exec.StdErr.ReadAll

  Do While exec.Status = 0
    WScript.Sleep 50
  Loop

  If stdout_text = "" Then stdout_text = exec.StdOut.ReadAll
  If stderr_text = "" Then stderr_text = exec.StdErr.ReadAll

  Set RunnerRun = MakeCompletedRun(spec("argv"), exec.ExitCode, stdout_text, stderr_text)
End Function
```

Key behaviors:
- `Exec` requires the command as a single string (shell-parsed), not an argv array. Need `JoinCommandLine` to build a properly quoted command string.
- `ExitCode` is available after the process terminates.
- Streams must be drained. The pattern is: read while `Status = 0` (running), then read final buffer.

### 3.2 Command line joining

VBScript's `Exec` passes through `cmd.exe`, so arguments must be shell-escaped. Simple quoting heuristic:

```vbscript
Function JoinCommandLine(argv)
  parts = ""
  For i = 0 To UBound(argv)
    part = argv(i)
    If InStr(part, " ") > 0 Or InStr(part, """") > 0 Then
      part = """" & Replace(part, """", "\""") & """"
    End If
    parts = parts & " " & part
  Next
  JoinCommandLine = Mid(parts, 2)  ' strip leading space
End Function
```

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
cscript //nologo vbscript/ccc.vbs "Fix the failing tests"
```

Users would typically alias `ccc` to `cscript //nologo <path>\ccc.vbs`.

### Behavior

- Exactly one unnamed argument required
- Usage message on wrong arg count, exit 1
- Prompt trimmed, empty rejected, exit 1
- Stdout/stderr forwarded, exit code forwarded via `WScript.Quit`
- `CCC_REAL_OPENCODE` env var support: override the binary name in `BuildPromptSpec` or in `JoinCommandLine`

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
Sub Assert(condition, name)
  If condition Then
    WScript.Echo "  PASS: " & name
  Else
    WScript.Echo "  FAIL: " & name
    WScript.Quit 1
  End If
End Sub

' Test BuildPromptSpec
On Error Resume Next
Set spec = BuildPromptSpec("  hello  ")
Assert Err.Number = 0, "BuildPromptSpec accepts padded prompt"
Assert spec("argv")(2) = "hello", "BuildPromptSpec trims prompt"

Set spec = BuildPromptSpec("")
Assert Err.Number <> 0, "BuildPromptSpec rejects empty prompt"
On Error GoTo 0
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

### 9.7 No module system

- All "library" code must be loaded via `ExecuteGlobal` or simply included in the same file
- For `ccc.vbs`, include the library functions directly or load `runner.vbs` with:

```vbscript
Set fso = CreateObject("Scripting.FileSystemObject")
lib = fso.OpenTextFile("runner.vbs").ReadAll
ExecuteGlobal lib
```

This is fragile with relative paths. The pragmatic approach: either duplicate the library functions in `ccc.vbs` or use a fixed relative path.

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
| `CCC_REAL_OPENCODE` | yes | yes | yes | yes | **yes** |

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

## 12. Open Questions

- Should `ccc.vbs` include the library inline (simpler deployment) or load `runner.vbs` via `ExecuteGlobal` (DRY but fragile paths)?
- Should we support `CCC_REAL_OPENCODE` by overriding the binary name or by using a custom `JoinCommandLine` that reads the env var?
- Is the `cmd.exe` quoting concern a blocking issue, or acceptable given Windows-only usage?
