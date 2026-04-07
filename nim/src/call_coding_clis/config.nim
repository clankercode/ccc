import std/options
import std/strutils
import std/os
import std/tables
import call_coding_clis/parser

type ConfigSection = enum
  csTopLevel
  csAlias
  csAbbreviations

proc loadConfig*(path: Option[string]): CccConfig =
  result = defaultConfig()

  let configPath = if path.isSome: path.get()
                   else: getHomeDir() / ".config" / "ccc" / "config"

  if not fileExists(configPath):
    return

  var section = csTopLevel
  var currentAlias = ""
  var currentAliasDef = AliasDef()

  for line in readFile(configPath).splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed[0] == '#':
      continue

    if trimmed[0] == '[' and trimmed.len > 1 and trimmed[^1] == ']':
      if currentAlias.len > 0 and section == csAlias:
        result.aliases[currentAlias] = currentAliasDef
        currentAlias = ""
        currentAliasDef = AliasDef()

      let sectionContent = trimmed[1..^2].strip()
      if sectionContent.startsWith("alias "):
        section = csAlias
        currentAlias = sectionContent[6..^1].strip()
        currentAliasDef = AliasDef()
      elif sectionContent == "abbreviations":
        section = csAbbreviations
      else:
        section = csTopLevel
      continue

    let eqPos = trimmed.find('=')
    if eqPos < 0:
      continue

    let key = trimmed[0..<eqPos].strip()
    let value = trimmed[eqPos + 1..^1].strip()

    case section
    of csTopLevel:
      case key
      of "default_runner":
        result.defaultRunner = value
      of "default_provider":
        result.defaultProvider = value
      of "default_model":
        result.defaultModel = value
      of "default_thinking":
        try:
          result.defaultThinking = some(parseInt(value))
        except ValueError:
          discard
      else:
        discard
    of csAlias:
      case key
      of "runner":
        currentAliasDef.runner = some(value)
      of "thinking":
        try:
          currentAliasDef.thinking = some(parseInt(value))
        except ValueError:
          discard
      of "provider":
        currentAliasDef.provider = some(value)
      of "model":
        currentAliasDef.model = some(value)
      else:
        discard
    of csAbbreviations:
      result.abbreviations[key] = value

  if currentAlias.len > 0 and section == csAlias:
    result.aliases[currentAlias] = currentAliasDef
