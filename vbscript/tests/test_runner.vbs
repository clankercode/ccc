Set fso = CreateObject("Scripting.FileSystemObject")
script_dir = fso.GetParentFolderName(WScript.ScriptFullName)
vbscript_dir = fso.GetParentFolderName(script_dir)

Set lib_file = fso.OpenTextFile(fso.BuildPath(vbscript_dir, "runner.vbs"))
ExecuteGlobal lib_file.ReadAll
lib_file.Close

Set spec_file = fso.OpenTextFile(fso.BuildPath(vbscript_dir, "build_prompt_spec.vbs"))
ExecuteGlobal spec_file.ReadAll
spec_file.Close

Dim pass_count, fail_count
pass_count = 0
fail_count = 0

Sub AssertEqual(actual, expected, name)
    If actual = expected Then
        WScript.Echo "  PASS: " & name
        pass_count = pass_count + 1
    Else
        WScript.Echo "  FAIL: " & name & " (expected [" & expected & "], got [" & actual & "])"
        fail_count = fail_count + 1
    End If
End Sub

Sub AssertTrue(condition, name)
    If condition Then
        WScript.Echo "  PASS: " & name
        pass_count = pass_count + 1
    Else
        WScript.Echo "  FAIL: " & name
        fail_count = fail_count + 1
    End If
End Sub

WScript.Echo "=== build_prompt_spec tests ==="

On Error Resume Next
Set spec = build_prompt_spec("  hello  ")
AssertTrue Err.Number = 0, "accepts padded prompt"
On Error GoTo 0
AssertEqual spec.Argv(2), "hello", "trims prompt"

On Error Resume Next
Set spec = build_prompt_spec("")
AssertTrue Err.Number <> 0, "rejects empty prompt"
Err.Clear
On Error GoTo 0

On Error Resume Next
Set spec = build_prompt_spec("   ")
AssertTrue Err.Number <> 0, "rejects whitespace-only prompt"
Err.Clear
On Error GoTo 0

On Error Resume Next
Set spec = build_prompt_spec(vbTab & "  ")
AssertTrue Err.Number <> 0, "rejects tab-and-space-only prompt"
Err.Clear
On Error GoTo 0

Set spec = build_prompt_spec("test")
AssertEqual spec.Argv(0), "opencode", "argv[0] is opencode by default"
AssertEqual spec.Argv(1), "run", "argv[1] is run"
AssertEqual spec.Argv(2), "test", "argv[2] is trimmed prompt"
AssertTrue IsEmpty(spec.StdinText), "stdin_text defaults to Empty"
AssertTrue IsEmpty(spec.Cwd), "cwd defaults to Empty"
AssertTrue spec.Env Is Nothing, "env defaults to Nothing"

WScript.Echo ""
WScript.Echo "=== CCC_REAL_OPENCODE tests ==="

Set shell_env = CreateObject("WScript.Shell")
shell_env.Environment("Process")("CCC_REAL_OPENCODE") = "myopencode"
Set spec = build_prompt_spec("test")
AssertEqual spec.Argv(0), "myopencode", "CCC_REAL_OPENCODE overrides binary"
shell_env.Environment("Process").Remove "CCC_REAL_OPENCODE"

Set spec = build_prompt_spec("test")
AssertEqual spec.Argv(0), "opencode", "fallback to opencode when env unset"

WScript.Echo ""
WScript.Echo "=== CompletedRun tests ==="

Set run_result = New CompletedRun
run_result.Argv = Array("echo", "hello")
run_result.ExitCode = 0
run_result.Stdout = "hello" & vbCrLf
run_result.Stderr = ""
AssertEqual run_result.ExitCode, 0, "exit_code is 0"
AssertEqual run_result.Stdout, "hello" & vbCrLf, "stdout matches"
AssertEqual run_result.Stderr, "", "stderr is empty"

WScript.Echo ""
WScript.Echo "=== CommandSpec tests ==="

Set spec = New CommandSpec
spec.Argv = Array("cmd", "/c", "echo hi")
AssertEqual spec.Argv(0), "cmd", "Argv element 0"
AssertEqual spec.Argv(1), "/c", "Argv element 1"
AssertEqual spec.Argv(2), "echo hi", "Argv element 2"
AssertTrue IsEmpty(spec.StdinText), "default StdinText is Empty"
AssertTrue IsEmpty(spec.Cwd), "default Cwd is Empty"
AssertTrue spec.Env Is Nothing, "default Env is Nothing"

WScript.Echo ""
WScript.Echo "=== Runner.Run tests ==="

Set spec = New CommandSpec
spec.Argv = Array("cmd", "/c", "echo hello")
Set run_result = Run(spec)
AssertEqual run_result.ExitCode, 0, "run captures zero exit code"
AssertTrue InStr(run_result.Stdout, "hello") > 0, "run captures stdout"

Set spec = New CommandSpec
spec.Argv = Array("cmd", "/c", "echo err>&2")
Set run_result = Run(spec)
AssertTrue InStr(run_result.Stderr, "err") > 0, "run captures stderr"

Set spec = New CommandSpec
spec.Argv = Array("cmd", "/c", "exit 42")
Set run_result = Run(spec)
AssertEqual run_result.ExitCode, 42, "run forwards nonzero exit code"

WScript.Echo ""
WScript.Echo "=== Startup failure tests ==="

Set spec = New CommandSpec
spec.Argv = Array("nonexistent_binary_that_does_not_exist_xyz")
Set run_result = Run(spec)
AssertEqual run_result.ExitCode, 1, "startup failure returns exit code 1"
AssertEqual run_result.Stdout, "", "startup failure has empty stdout"
AssertTrue InStr(run_result.Stderr, "failed to start") > 0, "startup failure has failed to start message"
AssertTrue InStr(run_result.Stderr, "nonexistent_binary_that_does_not_exist_xyz") > 0, "startup failure mentions binary name"

WScript.Echo ""
WScript.Echo "=== Stream tests ==="

Set spec = New CommandSpec
spec.Argv = Array("cmd", "/c", "echo streamed")
Dim stream_stdout_seen
stream_stdout_seen = ""
Set run_result = Stream(spec, GetRef("StreamCallback"))
AssertTrue InStr(stream_stdout_seen, "streamed") > 0, "stream callback received stdout"
AssertEqual run_result.ExitCode, 0, "stream returns completed run with exit code"

WScript.Echo ""
WScript.Echo pass_count & " passed, " & fail_count & " failed"

If fail_count > 0 Then WScript.Quit 1

Function StreamCallback(stream_name, data)
    If stream_name = "stdout" Then
        stream_stdout_seen = data
    End If
End Function
