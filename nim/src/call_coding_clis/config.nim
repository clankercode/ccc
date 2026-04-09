import std/options
import std/strutils
import std/os
import std/tables
import call_coding_clis/parser

type ConfigSection = enum
  csTopLevel
  csDefaults
  csAlias
  csAbbreviations

proc stripQuotes(value: string): string =
  let trimmed = value.strip()
  if trimmed.len >= 2:
    let first = trimmed[0]
    let last = trimmed[^1]
    if (first == '"' and last == '"') or (first == '\'' and last == '\''):
      if trimmed.len <= 2:
        return ""
      return trimmed[1..^2]
  return trimmed

proc applyTopLevelKey(cfg: var CccConfig, key, rawValue: string) =
  let value = stripQuotes(rawValue)
  case key
  of "default_runner", "runner":
    if value.len > 0:
      cfg.defaultRunner = value
  of "default_provider", "provider":
    cfg.defaultProvider = value
  of "default_model", "model":
    cfg.defaultModel = value
  of "default_thinking", "thinking":
    try:
      cfg.defaultThinking = some(parseInt(value))
    except ValueError:
      discard
  else:
    discard

proc applyAliasKey(defn: var AliasDef, key, rawValue: string) =
  let value = stripQuotes(rawValue)
  case key
  of "runner":
    if value.len > 0:
      defn.runner = some(value)
  of "thinking":
    try:
      defn.thinking = some(parseInt(value))
    except ValueError:
      discard
  of "provider":
    if value.len > 0:
      defn.provider = some(value)
  of "model":
    if value.len > 0:
      defn.model = some(value)
  of "agent":
    if value.len > 0:
      defn.agent = some(value)
  else:
    discard

proc storeAlias(cfg: var CccConfig, name: string, defn: AliasDef) =
  if name.len > 0:
    cfg.aliases[name] = defn

proc loadConfigText(configText: string): CccConfig =
  result = defaultConfig()

  var section = csTopLevel
  var currentAlias = ""
  var currentAliasDef = AliasDef()

  for line in configText.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed[0] == '#':
      continue

    if trimmed[0] == '[' and trimmed.len > 1 and trimmed[^1] == ']':
      if section == csAlias:
        storeAlias(result, currentAlias, currentAliasDef)
        currentAlias = ""
        currentAliasDef = AliasDef()

      let sectionContent = trimmed[1..^2].strip()
      if sectionContent == "defaults":
        section = csDefaults
      elif sectionContent == "abbreviations":
        section = csAbbreviations
      elif sectionContent.startsWith("aliases."):
        section = csAlias
        currentAlias = sectionContent["aliases.".len..^1].strip()
        currentAliasDef = AliasDef()
      elif sectionContent.startsWith("alias "):
        section = csAlias
        currentAlias = sectionContent["alias ".len..^1].strip()
        currentAliasDef = AliasDef()
      else:
        section = csTopLevel
      continue

    let eqPos = trimmed.find('=')
    if eqPos < 0:
      continue

    let key = trimmed[0..<eqPos].strip()
    let value = trimmed[eqPos + 1..^1].strip()

    case section
    of csTopLevel, csDefaults:
      applyTopLevelKey(result, key, value)
    of csAlias:
      applyAliasKey(currentAliasDef, key, value)
    of csAbbreviations:
      result.abbreviations[key] = stripQuotes(value)

  if section == csAlias and currentAlias.len > 0:
    storeAlias(result, currentAlias, currentAliasDef)

proc loadConfigFile(path: string): CccConfig =
  if not fileExists(path):
    return defaultConfig()
  return loadConfigText(readFile(path))

proc defaultConfigPaths(): seq[string] =
  let xdgConfigHome = getEnv("XDG_CONFIG_HOME")
  if xdgConfigHome.len > 0:
    result.add(xdgConfigHome / "ccc" / "config.toml")
  result.add(getHomeDir() / ".config" / "ccc" / "config.toml")

proc loadConfig*(path: Option[string]): CccConfig =
  if path.isSome:
    return loadConfigFile(path.get())

  for configPath in defaultConfigPaths():
    if fileExists(configPath):
      return loadConfigFile(configPath)

  result = defaultConfig()
