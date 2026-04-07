import std/unittest
import std/options
import std/tables
import call_coding_clis/parser

suite "parseArgs":
  test "prompt only":
    let p = parseArgs(@["hello world"])
    check p.runner.isNone
    check p.prompt == "hello world"

  test "runner selector":
    let p = parseArgs(@["claude", "do stuff"])
    check p.runner == some("claude")
    check p.prompt == "do stuff"

  test "thinking":
    let p = parseArgs(@["+2", "think hard"])
    check p.thinking == some(2)
    check p.prompt == "think hard"

  test "provider and model":
    let p = parseArgs(@[":anthropic:opus", "hi"])
    check p.provider == some("anthropic")
    check p.model == some("opus")
    check p.prompt == "hi"

  test "model only":
    let p = parseArgs(@[":gpt-4", "hi"])
    check p.model == some("gpt-4")
    check p.provider.isNone
    check p.prompt == "hi"

  test "alias":
    let p = parseArgs(@["@fast", "go"])
    check p.alias == some("fast")
    check p.prompt == "go"

  test "full combo":
    let p = parseArgs(@["claude", "+3", ":anthropic:opus", "@deep", "do it"])
    check p.runner == some("claude")
    check p.thinking == some(3)
    check p.provider == some("anthropic")
    check p.model == some("opus")
    check p.alias == some("deep")
    check p.prompt == "do it"

  test "runner case insensitive":
    let p = parseArgs(@["Claude", "hi"])
    check p.runner == some("claude")

  test "positional stops special parsing":
    let p = parseArgs(@["hello", "+2"])
    check p.thinking.isNone
    check p.prompt == "hello +2"

  test "multiple positional tokens":
    let p = parseArgs(@["fix", "the", "bug"])
    check p.prompt == "fix the bug"

  test "runner abbreviation oc":
    let p = parseArgs(@["oc", "test"])
    check p.runner == some("oc")

  test "thinking zero":
    let p = parseArgs(@["+0", "prompt"])
    check p.thinking == some(0)

suite "resolveCommand":
  test "default runner":
    let p = parseArgs(@["hello"])
    let (argv, env) = resolveCommand(p, none(CccConfig))
    check argv == @["opencode", "run", "hello"]
    check env.len == 0

  test "claude runner":
    let p = parseArgs(@["claude", "hello"])
    let (argv, env) = resolveCommand(p, none(CccConfig))
    check argv == @["claude", "hello"]
    check env.len == 0

  test "claude thinking +3":
    let p = parseArgs(@["claude", "+3", "hello"])
    let (argv, _) = resolveCommand(p, none(CccConfig))
    check argv == @["claude", "--thinking", "high", "hello"]

  test "claude thinking +0":
    let p = parseArgs(@["claude", "+0", "hello"])
    let (argv, _) = resolveCommand(p, none(CccConfig))
    check argv == @["claude", "--no-thinking", "hello"]

  test "codex model flag":
    let p = parseArgs(@["codex", ":gpt-4", "hello"])
    let (argv, _) = resolveCommand(p, none(CccConfig))
    check argv == @["codex", "--model", "gpt-4", "hello"]

  test "provider sets env":
    let p = parseArgs(@[":anthropic:opus", "hello"])
    let (argv, env) = resolveCommand(p, none(CccConfig))
    check argv == @["opencode", "run", "hello"]
    check env.hasKey("CCC_PROVIDER")
    check env["CCC_PROVIDER"] == "anthropic"

  test "empty prompt raises ValueError":
    let p = parseArgs(@["+2"])
    expect ValueError:
      discard resolveCommand(p, none(CccConfig))

  test "empty argv raises ValueError":
    let p = parseArgs(@[])
    expect ValueError:
      discard resolveCommand(p, none(CccConfig))

  test "alias resolution":
    var cfg = defaultConfig()
    cfg.aliases["fast"] = AliasDef(
      runner: some("claude"),
      thinking: some(1),
      provider: none(string),
      model: none(string)
    )
    let p = parseArgs(@["@fast", "hello"])
    let (argv, _) = resolveCommand(p, some(cfg))
    check argv == @["claude", "--thinking", "low", "hello"]

  test "alias with provider and model":
    var cfg = defaultConfig()
    cfg.aliases["deep"] = AliasDef(
      runner: some("claude"),
      thinking: some(4),
      provider: some("anthropic"),
      model: some("opus")
    )
    let p = parseArgs(@["@deep", "hello"])
    let (argv, env) = resolveCommand(p, some(cfg))
    check argv[0] == "claude"
    check env["CCC_PROVIDER"] == "anthropic"

  test "abbreviation resolution":
    var cfg = defaultConfig()
    cfg.abbreviations["c"] = "kimi"
    let p = parseArgs(@["c", "hello"])
    let (argv, _) = resolveCommand(p, some(cfg))
    check argv == @["kimi", "hello"]

  test "config default thinking":
    var cfg = defaultConfig()
    cfg.defaultThinking = some(2)
    let p = parseArgs(@["claude", "hello"])
    let (argv, _) = resolveCommand(p, some(cfg))
    check argv == @["claude", "--thinking", "medium", "hello"]

  test "config default provider":
    var cfg = defaultConfig()
    cfg.defaultProvider = "openai"
    let p = parseArgs(@["hello"])
    let (_, env) = resolveCommand(p, some(cfg))
    check env["CCC_PROVIDER"] == "openai"

  test "config default model":
    var cfg = defaultConfig()
    cfg.defaultModel = "gpt-4"
    let p = parseArgs(@["codex", "hello"])
    let (argv, _) = resolveCommand(p, some(cfg))
    check argv == @["codex", "--model", "gpt-4", "hello"]
