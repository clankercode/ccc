import std/options
import std/tables
import std/strutils

type
  RunnerInfo* = object
    binary*: string
    extraArgs*: seq[string]
    thinkingFlags*: Table[int, seq[string]]
    providerFlag*: string
    modelFlag*: string
    agentFlag*: string

  ParsedArgs* = object
    runner*: Option[string]
    thinking*: Option[int]
    provider*: Option[string]
    model*: Option[string]
    alias*: Option[string]
    prompt*: string

  AliasDef* = object
    runner*: Option[string]
    thinking*: Option[int]
    provider*: Option[string]
    model*: Option[string]
    agent*: Option[string]

  CccConfig* = object
    defaultRunner*: string
    defaultProvider*: string
    defaultModel*: string
    defaultThinking*: Option[int]
    aliases*: Table[string, AliasDef]
    abbreviations*: Table[string, string]

const RUNNER_NAMES = [
  "opencode", "claude", "kimi", "codex", "crush",
  "oc", "cc", "c", "k", "rc", "cr", "roocode", "pi"
]

proc defaultConfig*(): CccConfig =
  CccConfig(
    defaultRunner: "oc",
    defaultProvider: "",
    defaultModel: "",
    defaultThinking: none(int),
    aliases: initTable[string, AliasDef](),
    abbreviations: initTable[string, string]()
  )

proc isRunnerSelector(s: string): bool =
  let lower = s.toLowerAscii()
  for name in RUNNER_NAMES:
    if lower == name:
      return true
  return false

proc parseThinking(s: string): Option[int] =
  if s.len == 2 and s[0] == '+' and s[1] in {'0', '1', '2', '3', '4'}:
    return some(ord(s[1]) - ord('0'))
  return none(int)

proc matchProviderModel(s: string): Option[tuple[provider: string, model: string]] =
  if s.len < 4 or s[0] != ':':
    return none(tuple[provider: string, model: string])
  let rest = s[1..^1]
  let colonPos = rest.find(':')
  if colonPos < 1 or colonPos == rest.len - 1:
    return none(tuple[provider: string, model: string])
  let provider = rest[0..<colonPos]
  let model = rest[colonPos + 1..^1]
  for ch in provider:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
      return none(tuple[provider: string, model: string])
  for ch in model:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '.', '_', '-'}:
      return none(tuple[provider: string, model: string])
  return some((provider, model))

proc matchModelOnly(s: string): Option[string] =
  if s.len < 2 or s[0] != ':':
    return none(string)
  let model = s[1..^1]
  if model.find(':') >= 0:
    return none(string)
  for ch in model:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '.', '_', '-'}:
      return none(string)
  return some(model)

proc matchAlias(s: string): Option[string] =
  if s.len < 2 or s[0] != '@':
    return none(string)
  let name = s[1..^1]
  for ch in name:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
      return none(string)
  return some(name)

proc runnerRegistry*(): Table[string, RunnerInfo] =
  result = initTable[string, RunnerInfo]()

  var claudeThinking = initTable[int, seq[string]]()
  claudeThinking[0] = @["--no-thinking"]
  claudeThinking[1] = @["--thinking", "low"]
  claudeThinking[2] = @["--thinking", "medium"]
  claudeThinking[3] = @["--thinking", "high"]
  claudeThinking[4] = @["--thinking", "max"]

  var kimiThinking = initTable[int, seq[string]]()
  kimiThinking[0] = @["--no-think"]
  kimiThinking[1] = @["--think", "low"]
  kimiThinking[2] = @["--think", "medium"]
  kimiThinking[3] = @["--think", "high"]
  kimiThinking[4] = @["--think", "max"]

  let emptyThinking = initTable[int, seq[string]]()

  let opencodeInfo = RunnerInfo(
    binary: "opencode",
    extraArgs: @["run"],
    thinkingFlags: emptyThinking,
    providerFlag: "",
    modelFlag: "",
    agentFlag: "--agent"
  )
  let claudeInfo = RunnerInfo(
    binary: "claude",
    extraArgs: @[],
    thinkingFlags: claudeThinking,
    providerFlag: "",
    modelFlag: "--model",
    agentFlag: "--agent"
  )
  let kimiInfo = RunnerInfo(
    binary: "kimi",
    extraArgs: @[],
    thinkingFlags: kimiThinking,
    providerFlag: "",
    modelFlag: "--model",
    agentFlag: "--agent"
  )
  let codexInfo = RunnerInfo(
    binary: "codex",
    extraArgs: @[],
    thinkingFlags: emptyThinking,
    providerFlag: "",
    modelFlag: "--model",
    agentFlag: ""
  )
  let crushInfo = RunnerInfo(
    binary: "crush",
    extraArgs: @[],
    thinkingFlags: emptyThinking,
    providerFlag: "",
    modelFlag: "",
    agentFlag: ""
  )

  result["opencode"] = opencodeInfo
  result["claude"] = claudeInfo
  result["kimi"] = kimiInfo
  result["codex"] = codexInfo
  result["crush"] = crushInfo
  result["oc"] = opencodeInfo
  result["cc"] = claudeInfo
  result["c"] = claudeInfo
  result["k"] = kimiInfo
  result["rc"] = codexInfo
  result["cr"] = crushInfo

proc parseArgs*(argv: seq[string]): ParsedArgs =
  result = ParsedArgs()
  var positional: seq[string] = @[]

  for token in argv:
    var handled = false

    if positional.len == 0:
      if not handled and isRunnerSelector(token) and result.runner.isNone:
        result.runner = some(token.toLowerAscii())
        handled = true

      if not handled:
        let t = parseThinking(token)
        if t.isSome:
          result.thinking = t
          handled = true

      if not handled:
        let pm = matchProviderModel(token)
        if pm.isSome:
          result.provider = some(pm.get().provider)
          result.model = some(pm.get().model)
          handled = true

      if not handled:
        let m = matchModelOnly(token)
        if m.isSome:
          result.model = m
          handled = true

      if not handled:
        let a = matchAlias(token)
        if a.isSome and result.alias.isNone:
          result.alias = a
          handled = true

    if not handled:
      positional.add(token)

  result.prompt = positional.join(" ")

proc resolveRunnerName(name: Option[string], config: CccConfig): string =
  if name.isNone:
    return config.defaultRunner
  let n = name.get()
  if config.abbreviations.hasKey(n):
    return config.abbreviations[n]
  return n

proc resolveCommand*(parsed: ParsedArgs, config: Option[CccConfig]): tuple[argv: seq[string], env: Table[string, string], warnings: seq[string]] =
  let cfg = if config.isSome: config.get() else: defaultConfig()
  let registry = runnerRegistry()

  var runnerName = resolveRunnerName(parsed.runner, cfg)

  var info: RunnerInfo
  if registry.hasKey(runnerName):
    info = registry[runnerName]
  elif registry.hasKey(cfg.defaultRunner):
    info = registry[cfg.defaultRunner]
  else:
    info = registry["opencode"]

  var aliasDef: Option[AliasDef] = none(AliasDef)
  if parsed.alias.isSome:
    let aliasName = parsed.alias.get()
    if cfg.aliases.hasKey(aliasName):
      aliasDef = some(cfg.aliases[aliasName])

  var effectiveRunnerName = runnerName
  if aliasDef.isSome:
    let ad = aliasDef.get()
    if ad.runner.isSome and parsed.runner.isNone:
      let effectiveRunner = resolveRunnerName(ad.runner, cfg)
      effectiveRunnerName = effectiveRunner
      if registry.hasKey(effectiveRunner):
        info = registry[effectiveRunner]

  result.argv = @[info.binary]
  for arg in info.extraArgs:
    result.argv.add(arg)

  var effectiveThinking = parsed.thinking
  if effectiveThinking.isNone and aliasDef.isSome:
    let ad = aliasDef.get()
    if ad.thinking.isSome:
      effectiveThinking = ad.thinking
  if effectiveThinking.isNone:
    effectiveThinking = cfg.defaultThinking
  if effectiveThinking.isSome:
    let lvl = effectiveThinking.get()
    if info.thinkingFlags.hasKey(lvl):
      for flag in info.thinkingFlags[lvl]:
        result.argv.add(flag)

  var effectiveProvider = parsed.provider
  if effectiveProvider.isNone and aliasDef.isSome:
    let ad = aliasDef.get()
    if ad.provider.isSome:
      effectiveProvider = ad.provider
  if effectiveProvider.isNone and cfg.defaultProvider.len > 0:
    effectiveProvider = some(cfg.defaultProvider)

  var effectiveModel = parsed.model
  if effectiveModel.isNone and aliasDef.isSome:
    let ad = aliasDef.get()
    if ad.model.isSome:
      effectiveModel = ad.model
  if effectiveModel.isNone and cfg.defaultModel.len > 0:
    effectiveModel = some(cfg.defaultModel)

  if effectiveModel.isSome and effectiveModel.get().len > 0 and info.modelFlag.len > 0:
    result.argv.add(info.modelFlag)
    result.argv.add(effectiveModel.get())

  result.env = initTable[string, string]()
  if effectiveProvider.isSome and effectiveProvider.get().len > 0:
    result.env["CCC_PROVIDER"] = effectiveProvider.get()

  var effectiveAgent: Option[string] = none(string)
  if parsed.alias.isSome and aliasDef.isNone:
    effectiveAgent = some(parsed.alias.get())
  elif aliasDef.isSome:
    let ad = aliasDef.get()
    if ad.agent.isSome:
      effectiveAgent = ad.agent

  if effectiveAgent.isSome and effectiveAgent.get().len > 0:
    if info.agentFlag.len > 0:
      result.argv.add(info.agentFlag)
      result.argv.add(effectiveAgent.get())
    else:
      result.warnings.add(
        "warning: runner \"" & effectiveRunnerName & "\" does not support agents; ignoring @" &
        effectiveAgent.get()
      )

  let prompt = parsed.prompt.strip()
  if prompt.len == 0:
    raise newException(ValueError, "prompt must not be empty")

  result.argv.add(prompt)
