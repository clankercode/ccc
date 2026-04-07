Set fso = CreateObject("Scripting.FileSystemObject")
script_dir = fso.GetParentFolderName(WScript.ScriptFullName)

Set lib_file = fso.OpenTextFile(fso.BuildPath(script_dir, "runner.vbs"))
ExecuteGlobal lib_file.ReadAll
lib_file.Close

Set spec_file = fso.OpenTextFile(fso.BuildPath(script_dir, "build_prompt_spec.vbs"))
ExecuteGlobal spec_file.ReadAll
spec_file.Close

Set parser_file = fso.OpenTextFile(fso.BuildPath(script_dir, "src\parser.vbs"))
ExecuteGlobal parser_file.ReadAll
parser_file.Close

Set config_file = fso.OpenTextFile(fso.BuildPath(script_dir, "src\config.vbs"))
ExecuteGlobal config_file.ReadAll
config_file.Close

Set args = WScript.Arguments.Unnamed

If args.Count = 0 Then
    WScript.StdErr.WriteLine "usage: ccc ""<Prompt>"""
    WScript.Quit 1
End If

If args.Count = 1 Then
    prompt = args(0)

    On Error Resume Next
    Set spec = build_prompt_spec(prompt)
    If Err.Number <> 0 Then
        WScript.StdErr.WriteLine Err.Description
        WScript.Quit 1
    End If
    On Error GoTo 0

    Set result = Run(spec)
Else
    ReDim inputArgs(args.Count - 1)
    For i = 0 To args.Count - 1
        inputArgs(i) = args(i)
    Next

    Set parsed = parseArgs(inputArgs)

    Set shell = CreateObject("WScript.Shell")
    configPath = shell.ExpandEnvironmentStrings("%CCC_CONFIG%")
    If configPath = "%CCC_CONFIG%" Then
        configPath = shell.ExpandEnvironmentStrings("%USERPROFILE%") & "\.ccc\config"
    End If

    Set config = loadConfig(configPath)

    On Error Resume Next
    Set resolved = resolveCommand(parsed, config)
    If Err.Number <> 0 Then
        WScript.StdErr.WriteLine Err.Description
        WScript.Quit 1
    End If
    On Error GoTo 0

    Set spec = New CommandSpec
    spec.Argv = resolved("argv")
    If resolved("env").Count > 0 Then
        Set spec.Env = resolved("env")
    End If

    Set result = Run(spec)
End If

If result.Stdout <> "" Then WScript.StdOut.Write result.Stdout
If result.Stderr <> "" Then WScript.StdErr.Write result.Stderr

WScript.Quit result.ExitCode
