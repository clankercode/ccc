Function loadConfig(path)
    Set loadConfig = New CccConfig

    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FileExists(path) Then
        Exit Function
    End If

    Set ts = fso.OpenTextFile(path, 1)
    currentSection = ""
    currentAliasName = ""

    Do Until ts.AtEndOfStream
        line = Trim(ts.ReadLine)

        If Len(line) = 0 Then
        ElseIf Left(line, 1) = "#" Then
        ElseIf Left(line, 1) = "'" Then
        ElseIf Left(line, 1) = "[" And Right(line, 1) = "]" Then
            currentSection = Mid(line, 2, Len(line) - 2)
            currentAliasName = ""
            If Len(currentSection) > 6 Then
                If LCase(Left(currentSection, 6)) = "alias." Then
                    currentAliasName = Mid(currentSection, 7)
                    Set loadConfig.Aliases(currentAliasName) = New AliasDef
                End If
            End If
        ElseIf LCase(currentSection) = "abbreviations" Then
            eqPos = InStr(line, "=")
            If eqPos > 1 Then
                aKey = Trim(Left(line, eqPos - 1))
                aVal = Trim(Mid(line, eqPos + 1))
                If Len(aKey) > 0 And Len(aVal) > 0 Then
                    loadConfig.Abbreviations(aKey) = aVal
                End If
            End If
        ElseIf Len(currentAliasName) > 0 Then
            eqPos = InStr(line, "=")
            If eqPos > 1 Then
                aKey = LCase(Trim(Left(line, eqPos - 1)))
                aVal = Trim(Mid(line, eqPos + 1))
                Set aliasDef = loadConfig.Aliases(currentAliasName)
                Select Case aKey
                    Case "runner"
                        aliasDef.Runner = aVal
                    Case "thinking"
                        If IsNumeric(aVal) Then aliasDef.Thinking = CInt(aVal)
                    Case "provider"
                        aliasDef.Provider = aVal
                    Case "model"
                        aliasDef.Model = aVal
                End Select
            End If
        Else
            eqPos = InStr(line, "=")
            If eqPos > 1 Then
                aKey = LCase(Trim(Left(line, eqPos - 1)))
                aVal = Trim(Mid(line, eqPos + 1))
                Select Case aKey
                    Case "default_runner"
                        If Len(aVal) > 0 Then loadConfig.DefaultRunner = aVal
                    Case "default_provider"
                        loadConfig.DefaultProvider = aVal
                    Case "default_model"
                        loadConfig.DefaultModel = aVal
                    Case "default_thinking"
                        If Len(aVal) > 0 And IsNumeric(aVal) Then
                            loadConfig.DefaultThinking = CInt(aVal)
                        End If
                End Select
            End If
        End If
    Loop

    ts.Close
End Function
