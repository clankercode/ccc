Set fso = CreateObject("Scripting.FileSystemObject")
script_dir = fso.GetParentFolderName(WScript.ScriptFullName)

Set lib_file = fso.OpenTextFile(fso.BuildPath(script_dir, "runner.vbs"))
ExecuteGlobal lib_file.ReadAll
lib_file.Close

Set spec_file = fso.OpenTextFile(fso.BuildPath(script_dir, "build_prompt_spec.vbs"))
ExecuteGlobal spec_file.ReadAll
spec_file.Close

Set args = WScript.Arguments.Unnamed
If args.Count <> 1 Then
    WScript.StdErr.WriteLine "usage: ccc ""<Prompt>"""
    WScript.Quit 1
End If

prompt = args(0)

On Error Resume Next
Set spec = build_prompt_spec(prompt)
If Err.Number <> 0 Then
    WScript.StdErr.WriteLine Err.Description
    WScript.Quit 1
End If
On Error GoTo 0

Set result = Run(spec)

If result.Stdout <> "" Then WScript.StdOut.Write result.Stdout
If result.Stderr <> "" Then WScript.StdErr.Write result.Stderr

WScript.Quit result.ExitCode
