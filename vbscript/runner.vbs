Class CommandSpec
    Public Argv
    Public StdinText
    Public Cwd
    Public Env

    Private Sub Class_Initialize()
        StdinText = Empty
        Cwd = Empty
        Set Env = Nothing
    End Sub
End Class

Class CompletedRun
    Public Argv
    Public ExitCode
    Public Stdout
    Public Stderr

    Private Sub Class_Initialize()
        ExitCode = 0
        Stdout = ""
        Stderr = ""
    End Sub
End Class

Function JoinCommandLine(argv)
    parts = ""
    For i = 0 To UBound(argv)
        part = argv(i)
        part = Replace(part, """", "\""")
        quoted_arg = """" & part & """"
        If Len(parts) > 0 Then
            parts = parts & " " & quoted_arg
        Else
            parts = quoted_arg
        End If
    Next
    JoinCommandLine = parts
End Function

Function Run(spec)
    Set shell = CreateObject("WScript.Shell")

    old_cwd = ""
    If Not IsEmpty(spec.Cwd) Then
        If Not IsNull(spec.Cwd) Then
            If Len(spec.Cwd) > 0 Then
                old_cwd = shell.CurrentDirectory
                shell.CurrentDirectory = spec.Cwd
            End If
        End If
    End If

    If Not spec.Env Is Nothing Then
        For Each key In spec.Env
            shell.Environment("Process")(key) = spec.Env(key)
        Next
    End If

    cmd = JoinCommandLine(spec.Argv)

    On Error Resume Next
    Set exec_obj = shell.Exec(cmd)
    If Err.Number <> 0 Then
        stderr_msg = "failed to start " & spec.Argv(0) & ": " & Err.Description & vbCrLf
        On Error GoTo 0
        If Len(old_cwd) > 0 Then shell.CurrentDirectory = old_cwd
        Set result = New CompletedRun
        result.Argv = spec.Argv
        result.ExitCode = 1
        result.Stdout = ""
        result.Stderr = stderr_msg
        Set Run = result
        Exit Function
    End If
    On Error GoTo 0

    If Not IsEmpty(spec.StdinText) Then
        If Not IsNull(spec.StdinText) Then
            If Len(spec.StdinText) > 0 Then
                exec_obj.StdIn.Write spec.StdinText
                exec_obj.StdIn.Close
            End If
        End If
    End If

    Do While exec_obj.Status = 0
        WScript.Sleep 50
    Loop

    stdout_text = exec_obj.StdOut.ReadAll
    stderr_text = exec_obj.StdErr.ReadAll

    If Len(old_cwd) > 0 Then shell.CurrentDirectory = old_cwd

    Set result = New CompletedRun
    result.Argv = spec.Argv
    result.ExitCode = exec_obj.ExitCode
    result.Stdout = stdout_text
    result.Stderr = stderr_text
    Set Run = result
End Function

Function Stream(spec, callback)
    Set result = Run(spec)
    If Len(result.Stdout) > 0 Then
        callback "stdout", result.Stdout
    End If
    If Len(result.Stderr) > 0 Then
        callback "stderr", result.Stderr
    End If
    Set Stream = result
End Function
