Function GetOpencodeBinary()
    Set shell = CreateObject("WScript.Shell")
    expanded = shell.ExpandEnvironmentStrings("%CCC_REAL_OPENCODE%")
    If expanded = "%CCC_REAL_OPENCODE%" Then
        GetOpencodeBinary = "opencode"
    Else
        GetOpencodeBinary = expanded
    End If
End Function

Function build_prompt_spec(prompt)
    trimmed = Trim(prompt)
    If Len(trimmed) = 0 Then
        Err.Raise vbObjectError + 1, "build_prompt_spec", "prompt must not be empty"
    End If
    binary = GetOpencodeBinary()
    argv = Array(binary, "run", trimmed)
    Set spec = New CommandSpec
    spec.Argv = argv
    Set build_prompt_spec = spec
End Function
