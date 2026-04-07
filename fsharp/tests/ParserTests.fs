module ParserTests

open System
open Xunit
open CallCodingClis

[<Fact>]
let ``parseArgs prompt only`` () =
    let parsed = Parser.parseArgs [|"hello world"|]
    Assert.Equal("hello world", parsed.Prompt)
    Assert.True(parsed.Runner.IsNone)
    Assert.True(parsed.Thinking.IsNone)
    Assert.True(parsed.Provider.IsNone)
    Assert.True(parsed.Model.IsNone)
    Assert.True(parsed.Alias.IsNone)

[<Fact>]
let ``parseArgs runner selector cc`` () =
    let parsed = Parser.parseArgs [|"cc"; "fix bug"|]
    Assert.Equal(Some "cc", parsed.Runner)
    Assert.Equal("fix bug", parsed.Prompt)

[<Fact>]
let ``parseArgs runner selector opencode`` () =
    let parsed = Parser.parseArgs [|"opencode"; "hello"|]
    Assert.Equal(Some "opencode", parsed.Runner)
    Assert.Equal("hello", parsed.Prompt)

[<Fact>]
let ``parseArgs thinking level`` () =
    let parsed = Parser.parseArgs [|"+2"; "hello"|]
    Assert.Equal(Some 2, parsed.Thinking)
    Assert.Equal("hello", parsed.Prompt)

[<Fact>]
let ``parseArgs provider model`` () =
    let parsed = Parser.parseArgs [|":anthropic:claude-4"; "hello"|]
    Assert.Equal(Some "anthropic", parsed.Provider)
    Assert.Equal(Some "claude-4", parsed.Model)
    Assert.Equal("hello", parsed.Prompt)

[<Fact>]
let ``parseArgs model only`` () =
    let parsed = Parser.parseArgs [|":gpt-4o"; "hello"|]
    Assert.Equal(Some "gpt-4o", parsed.Model)
    Assert.True(parsed.Provider.IsNone)
    Assert.Equal("hello", parsed.Prompt)

[<Fact>]
let ``parseArgs alias`` () =
    let parsed = Parser.parseArgs [|"@work"; "hello"|]
    Assert.Equal(Some "work", parsed.Alias)
    Assert.Equal("hello", parsed.Prompt)

[<Fact>]
let ``parseArgs full combo`` () =
    let parsed = Parser.parseArgs [|"cc"; "+3"; ":anthropic:claude-4"; "@fast"; "fix tests"|]
    Assert.Equal(Some "cc", parsed.Runner)
    Assert.Equal(Some 3, parsed.Thinking)
    Assert.Equal(Some "anthropic", parsed.Provider)
    Assert.Equal(Some "claude-4", parsed.Model)
    Assert.Equal(Some "fast", parsed.Alias)
    Assert.Equal("fix tests", parsed.Prompt)

[<Fact>]
let ``parseArgs runner case insensitive`` () =
    let parsed = Parser.parseArgs [|"CC"; "hello"|]
    Assert.Equal(Some "cc", parsed.Runner)

[<Fact>]
let ``parseArgs thinking zero`` () =
    let parsed = Parser.parseArgs [|"+0"; "hello"|]
    Assert.Equal(Some 0, parsed.Thinking)

[<Fact>]
let ``parseArgs thinking out of range not matched`` () =
    let parsed = Parser.parseArgs [|"+5"; "hello"|]
    Assert.True(parsed.Thinking.IsNone)
    Assert.Equal("+5 hello", parsed.Prompt)

[<Fact>]
let ``parseArgs tokens after prompt become part of prompt`` () =
    let parsed = Parser.parseArgs [|"cc"; "hello"; "+2"|]
    Assert.Equal(Some "cc", parsed.Runner)
    Assert.Equal("hello +2", parsed.Prompt)

[<Fact>]
let ``parseArgs multi word prompt`` () =
    let parsed = Parser.parseArgs [|"fix"; "the"; "bug"|]
    Assert.Equal("fix the bug", parsed.Prompt)

[<Fact>]
let ``resolveCommand default runner is opencode`` () =
    let parsed = { Runner = None; Thinking = None; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed None
    Assert.Equal("opencode", List.head argv)
    Assert.Contains("run", argv)
    Assert.Contains("hello", argv)

[<Fact>]
let ``resolveCommand claude runner`` () =
    let parsed = { Runner = Some "cc"; Thinking = None; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed None
    Assert.Equal("claude", List.head argv)
    Assert.DoesNotContain("run", argv)
    Assert.Contains("hello", argv)

[<Fact>]
let ``resolveCommand thinking flags for claude`` () =
    let parsed = { Runner = Some "cc"; Thinking = Some 2; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed None
    Assert.Contains("--thinking", argv)
    Assert.Contains("medium", argv)

[<Fact>]
let ``resolveCommand thinking zero for claude`` () =
    let parsed = { Runner = Some "cc"; Thinking = Some 0; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed None
    Assert.Contains("--no-thinking", argv)

[<Fact>]
let ``resolveCommand model flag for claude`` () =
    let parsed = { Runner = Some "cc"; Thinking = None; Provider = None; Model = Some "claude-4"; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed None
    Assert.Contains("--model", argv)
    Assert.Contains("claude-4", argv)

[<Fact>]
let ``resolveCommand provider sets env`` () =
    let parsed = { Runner = None; Thinking = None; Provider = Some "anthropic"; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed None
    Assert.Equal(Some "anthropic", env.TryFind("CCC_PROVIDER"))

[<Fact>]
let ``resolveCommand empty prompt raises`` () =
    let parsed = { Runner = None; Thinking = None; Provider = None; Model = None; Alias = None; Prompt = "   " }
    Assert.ThrowsAny<Exception>(fun () -> Parser.resolveCommand parsed None |> ignore) |> ignore

[<Fact>]
let ``resolveCommand config default runner`` () =
    let config = { Config.defaultConfig with DefaultRunner = "cc" }
    let parsed = { Runner = None; Thinking = None; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed (Some config)
    Assert.Equal("claude", List.head argv)

[<Fact>]
let ``resolveCommand config default thinking`` () =
    let config = { Config.defaultConfig with DefaultRunner = "cc"; DefaultThinking = Some 1 }
    let parsed = { Runner = None; Thinking = None; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed (Some config)
    Assert.Contains("--thinking", argv)
    Assert.Contains("low", argv)

[<Fact>]
let ``resolveCommand config default model`` () =
    let config = { Config.defaultConfig with DefaultRunner = "cc"; DefaultModel = "claude-3.5" }
    let parsed = { Runner = None; Thinking = None; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed (Some config)
    Assert.Contains("--model", argv)
    Assert.Contains("claude-3.5", argv)

[<Fact>]
let ``resolveCommand config abbreviation`` () =
    let config = { Config.defaultConfig with Abbreviations = Map.ofList [("mycc", "cc")] }
    let parsed = { Runner = Some "mycc"; Thinking = None; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed (Some config)
    Assert.Equal("claude", List.head argv)

[<Fact>]
let ``resolveCommand alias provides defaults`` () =
    let alias = { Runner = Some "cc"; Thinking = Some 3; Provider = None; Model = Some "claude-4" }
    let config = { Config.defaultConfig with Aliases = Map.ofList [("work", alias)] }
    let parsed = { Runner = None; Thinking = None; Provider = None; Model = None; Alias = Some "work"; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed (Some config)
    Assert.Equal("claude", List.head argv)
    Assert.Contains("--thinking", argv)
    Assert.Contains("high", argv)
    Assert.Contains("--model", argv)
    Assert.Contains("claude-4", argv)

[<Fact>]
let ``resolveCommand explicit overrides alias`` () =
    let alias = { Runner = Some "cc"; Thinking = Some 3; Provider = None; Model = Some "claude-4" }
    let config = { Config.defaultConfig with Aliases = Map.ofList [("work", alias)] }
    let parsed = { Runner = Some "k"; Thinking = Some 1; Provider = None; Model = None; Alias = Some "work"; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed (Some config)
    Assert.Equal("kimi", List.head argv)
    Assert.Contains("--think", argv)
    Assert.Contains("low", argv)

[<Fact>]
let ``resolveCommand kimi thinking flags`` () =
    let parsed = { Runner = Some "k"; Thinking = Some 4; Provider = None; Model = None; Alias = None; Prompt = "hello" }
    let argv, env = Parser.resolveCommand parsed None
    Assert.Contains("--think", argv)
    Assert.Contains("max", argv)

[<Fact>]
let ``loadConfig missing file returns defaults`` () =
    let config = Config.loadConfig (Some "/nonexistent/path/config.toml")
    Assert.Equal("oc", config.DefaultRunner)
    Assert.True(config.Aliases.IsEmpty)

[<Fact>]
let ``loadConfig valid toml config`` () =
    let toml = """[defaults]
runner = "cc"
provider = "anthropic"
model = "claude-4"
thinking = 2

[abbreviations]
mycc = "cc"

[aliases.work]
runner = "cc"
thinking = 3
model = "claude-4"

[aliases.quick]
runner = "oc"
"""
    let tmpPath = System.IO.Path.GetTempFileName()
    try
        System.IO.File.WriteAllText(tmpPath, toml)
        let config = Config.loadConfig (Some tmpPath)
        Assert.Equal("cc", config.DefaultRunner)
        Assert.Equal("anthropic", config.DefaultProvider)
        Assert.Equal("claude-4", config.DefaultModel)
        Assert.Equal(Some 2, config.DefaultThinking)
        Assert.Equal(Some "cc", config.Abbreviations.TryFind("mycc"))
        Assert.True(config.Aliases.ContainsKey("work"))
        Assert.Equal(Some "cc", config.Aliases.["work"].Runner)
        Assert.Equal(Some 3, config.Aliases.["work"].Thinking)
        Assert.Equal(Some "claude-4", config.Aliases.["work"].Model)
        Assert.True(config.Aliases.ContainsKey("quick"))
        Assert.Equal(Some "oc", config.Aliases.["quick"].Runner)
    finally
        System.IO.File.Delete(tmpPath)

[<Fact>]
let ``loadConfig empty toml returns defaults`` () =
    let tmpPath = System.IO.Path.GetTempFileName()
    try
        System.IO.File.WriteAllText(tmpPath, "")
        let config = Config.loadConfig (Some tmpPath)
        Assert.Equal("oc", config.DefaultRunner)
    finally
        System.IO.File.Delete(tmpPath)

[<Fact>]
let ``runnerRegistry all selectors registered`` () =
    for sel in ["oc"; "cc"; "c"; "k"; "rc"; "cr"; "codex"; "claude"; "opencode"; "kimi"; "crush"] do
        Assert.True(Parser.runnerRegistry.ContainsKey(sel), sprintf "Missing selector: %s" sel)

[<Fact>]
let ``runnerRegistry abbreviations point to same info`` () =
    Assert.Equal(Parser.runnerRegistry.["oc"].Binary, Parser.runnerRegistry.["opencode"].Binary)
    Assert.Equal(Parser.runnerRegistry.["cc"].Binary, Parser.runnerRegistry.["claude"].Binary)
    Assert.Equal(Parser.runnerRegistry.["c"].Binary, Parser.runnerRegistry.["claude"].Binary)
    Assert.Equal(Parser.runnerRegistry.["k"].Binary, Parser.runnerRegistry.["kimi"].Binary)
