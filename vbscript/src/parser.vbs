Class RunnerInfo
    Public Binary
    Public ExtraArgs
    Public ThinkingFlags
    Public ProviderFlag
    Public ModelFlag

    Private Sub Class_Initialize()
        ExtraArgs = Array()
        Set ThinkingFlags = CreateObject("Scripting.Dictionary")
        ProviderFlag = ""
        ModelFlag = ""
    End Sub
End Class

Class ParsedArgs
    Public Runner
    Public Thinking
    Public Provider
    Public Model
    Public Alias
    Public Prompt

    Private Sub Class_Initialize()
        Runner = Empty
        Thinking = Empty
        Provider = Empty
        Model = Empty
        Alias = Empty
        Prompt = ""
    End Sub
End Class

Class AliasDef
    Public Runner
    Public Thinking
    Public Provider
    Public Model

    Private Sub Class_Initialize()
        Runner = Empty
        Thinking = Empty
        Provider = Empty
        Model = Empty
    End Sub
End Class

Class CccConfig
    Public DefaultRunner
    Public DefaultProvider
    Public DefaultModel
    Public DefaultThinking
    Public Aliases
    Public Abbreviations

    Private Sub Class_Initialize()
        DefaultRunner = "oc"
        DefaultProvider = ""
        DefaultModel = ""
        DefaultThinking = Empty
        Set Aliases = CreateObject("Scripting.Dictionary")
        Set Abbreviations = CreateObject("Scripting.Dictionary")
    End Sub
End Class

Dim RUNNER_REGISTRY
Set RUNNER_REGISTRY = Nothing

Function getRunnerRegistry()
    If Not RUNNER_REGISTRY Is Nothing Then
        Set getRunnerRegistry = RUNNER_REGISTRY
        Exit Function
    End If

    Set RUNNER_REGISTRY = CreateObject("Scripting.Dictionary")
    RUNNER_REGISTRY.CompareMode = vbTextCompare

    Set oc = New RunnerInfo
    oc.Binary = "opencode"
    oc.ExtraArgs = Array("run")
    Set RUNNER_REGISTRY("opencode") = oc

    Set cc = New RunnerInfo
    cc.Binary = "claude"
    cc.ThinkingFlags.Add 0, Array("--no-thinking")
    cc.ThinkingFlags.Add 1, Array("--thinking", "low")
    cc.ThinkingFlags.Add 2, Array("--thinking", "medium")
    cc.ThinkingFlags.Add 3, Array("--thinking", "high")
    cc.ThinkingFlags.Add 4, Array("--thinking", "max")
    cc.ModelFlag = "--model"
    Set RUNNER_REGISTRY("claude") = cc

    Set k = New RunnerInfo
    k.Binary = "kimi"
    k.ThinkingFlags.Add 0, Array("--no-think")
    k.ThinkingFlags.Add 1, Array("--think", "low")
    k.ThinkingFlags.Add 2, Array("--think", "medium")
    k.ThinkingFlags.Add 3, Array("--think", "high")
    k.ThinkingFlags.Add 4, Array("--think", "max")
    k.ModelFlag = "--model"
    Set RUNNER_REGISTRY("kimi") = k

    Set rc = New RunnerInfo
    rc.Binary = "codex"
    rc.ModelFlag = "--model"
    Set RUNNER_REGISTRY("codex") = rc

    Set cr = New RunnerInfo
    cr.Binary = "crush"
    Set RUNNER_REGISTRY("crush") = cr

    Set RUNNER_REGISTRY("oc") = oc
    Set RUNNER_REGISTRY("cc") = cc
    Set RUNNER_REGISTRY("c") = cc
    Set RUNNER_REGISTRY("k") = k
    Set RUNNER_REGISTRY("rc") = rc
    Set RUNNER_REGISTRY("cr") = cr

    Set getRunnerRegistry = RUNNER_REGISTRY
End Function

Function parseArgs(argv)
    Set parsed = New ParsedArgs
    positionalStr = ""

    Set runnerRe = New RegExp
    runnerRe.Pattern = "^(?:oc|cc|c|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$"
    runnerRe.IgnoreCase = True

    Set thinkingRe = New RegExp
    thinkingRe.Pattern = "^\+([0-4])$"

    Set providerModelRe = New RegExp
    providerModelRe.Pattern = "^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$"

    Set modelRe = New RegExp
    modelRe.Pattern = "^:([a-zA-Z0-9._-]+)$"

    Set aliasRe = New RegExp
    aliasRe.Pattern = "^@([a-zA-Z0-9_-]+)$"

    For i = 0 To UBound(argv)
        token = argv(i)

        If runnerRe.Test(token) And IsEmpty(parsed.Runner) And Len(positionalStr) = 0 Then
            parsed.Runner = LCase(token)
        ElseIf thinkingRe.Test(token) And Len(positionalStr) = 0 Then
            Set tMatches = thinkingRe.Execute(token)
            parsed.Thinking = CInt(tMatches(0).SubMatches(0))
        ElseIf providerModelRe.Test(token) And Len(positionalStr) = 0 Then
            Set pmMatches = providerModelRe.Execute(token)
            parsed.Provider = pmMatches(0).SubMatches(0)
            parsed.Model = pmMatches(0).SubMatches(1)
        ElseIf modelRe.Test(token) And Len(positionalStr) = 0 Then
            Set mMatches = modelRe.Execute(token)
            parsed.Model = mMatches(0).SubMatches(0)
        ElseIf aliasRe.Test(token) And IsEmpty(parsed.Alias) And Len(positionalStr) = 0 Then
            Set aMatches = aliasRe.Execute(token)
            parsed.Alias = aMatches(0).SubMatches(0)
        Else
            If Len(positionalStr) > 0 Then
                positionalStr = positionalStr & " " & token
            Else
                positionalStr = token
            End If
        End If
    Next

    parsed.Prompt = positionalStr
    Set parseArgs = parsed
End Function

Function resolveRunnerName(name, config)
    If IsEmpty(name) Then
        resolveRunnerName = config.DefaultRunner
        Exit Function
    End If
    If config.Abbreviations.Exists(name) Then
        resolveRunnerName = config.Abbreviations(name)
        Exit Function
    End If
    resolveRunnerName = name
End Function

Function resolveCommand(parsed, config)
    If config Is Nothing Then
        Set config = New CccConfig
    End If

    runnerName = resolveRunnerName(parsed.Runner, config)

    Set registry = getRunnerRegistry()

    If registry.Exists(runnerName) Then
        Set info = registry(runnerName)
    ElseIf registry.Exists(config.DefaultRunner) Then
        Set info = registry(config.DefaultRunner)
    Else
        Set info = registry("opencode")
    End If

    Set aliasDef = Nothing
    If Not IsEmpty(parsed.Alias) Then
        If config.Aliases.Exists(parsed.Alias) Then
            Set aliasDef = config.Aliases(parsed.Alias)
        End If
    End If

    If Not aliasDef Is Nothing Then
        If Not IsEmpty(aliasDef.Runner) And IsEmpty(parsed.Runner) Then
            effectiveRunnerName = resolveRunnerName(aliasDef.Runner, config)
            If registry.Exists(effectiveRunnerName) Then
                Set info = registry(effectiveRunnerName)
            End If
        End If
    End If

    ReDim cmdArgs(0)
    cmdArgs(0) = info.Binary
    argCount = 1

    For Each ea In info.ExtraArgs
        ReDim Preserve cmdArgs(argCount)
        cmdArgs(argCount) = ea
        argCount = argCount + 1
    Next

    effectiveThinking = parsed.Thinking
    If IsEmpty(effectiveThinking) And Not aliasDef Is Nothing Then
        If Not IsEmpty(aliasDef.Thinking) Then
            effectiveThinking = aliasDef.Thinking
        End If
    End If
    If IsEmpty(effectiveThinking) Then
        If Not IsEmpty(config.DefaultThinking) Then
            effectiveThinking = config.DefaultThinking
        End If
    End If
    If Not IsEmpty(effectiveThinking) Then
        If info.ThinkingFlags.Exists(effectiveThinking) Then
            flags = info.ThinkingFlags(effectiveThinking)
            For Each f In flags
                ReDim Preserve cmdArgs(argCount)
                cmdArgs(argCount) = f
                argCount = argCount + 1
            Next
        End If
    End If

    effectiveProvider = parsed.Provider
    If IsEmpty(effectiveProvider) And Not aliasDef Is Nothing Then
        If Not IsEmpty(aliasDef.Provider) Then
            effectiveProvider = aliasDef.Provider
        End If
    End If
    If IsEmpty(effectiveProvider) Then
        If Len(config.DefaultProvider) > 0 Then
            effectiveProvider = config.DefaultProvider
        End If
    End If

    effectiveModel = parsed.Model
    If IsEmpty(effectiveModel) And Not aliasDef Is Nothing Then
        If Not IsEmpty(aliasDef.Model) Then
            effectiveModel = aliasDef.Model
        End If
    End If
    If IsEmpty(effectiveModel) Then
        If Len(config.DefaultModel) > 0 Then
            effectiveModel = config.DefaultModel
        End If
    End If
    If Not IsEmpty(effectiveModel) And Len(info.ModelFlag) > 0 Then
        ReDim Preserve cmdArgs(argCount)
        cmdArgs(argCount) = info.ModelFlag
        argCount = argCount + 1
        ReDim Preserve cmdArgs(argCount)
        cmdArgs(argCount) = effectiveModel
        argCount = argCount + 1
    End If

    prompt = Trim(parsed.Prompt)
    If Len(prompt) = 0 Then
        Err.Raise vbObjectError + 1, "resolveCommand", "prompt must not be empty"
    End If

    ReDim Preserve cmdArgs(argCount)
    cmdArgs(argCount) = prompt

    Set result = CreateObject("Scripting.Dictionary")
    result("argv") = cmdArgs
    Set envOverrides = CreateObject("Scripting.Dictionary")
    If Not IsEmpty(effectiveProvider) And Len(effectiveProvider) > 0 Then
        envOverrides("CCC_PROVIDER") = effectiveProvider
    End If
    Set result("env") = envOverrides

    Set resolveCommand = result
End Function
