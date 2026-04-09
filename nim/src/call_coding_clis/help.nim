import std/os
import std/osproc
import std/strutils
import std/streams
import std/tables
import call_coding_clis/parser

type
  RunnerEntry = tuple[name: string, alias: string]

const CANONICAL_RUNNERS: seq[RunnerEntry] = @[
  ("opencode", "oc"),
  ("claude", "cc"),
  ("kimi", "k"),
  ("codex", "rc"),
  ("crush", "cr"),
]

const HELP_TEXT = """ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
"""

proc getVersion(binary: string): string =
  try:
    var p = startProcess(command = binary, args = @["--version"], options = {poUsePath})
    let outStrm = p.outputStream()
    let output = outStrm.readAll()
    let exitCode = p.waitForExit(3000)
    if exitCode == 0 and output.strip().len > 0:
      result = output.strip().splitLines()[0]
    p.close()
  except OSError, ValueError, IOError:
    discard

proc runnerChecklist(): string =
  let registry = runnerRegistry()
  var lines: seq[string] = @["Runners:"]
  for (name, _) in CANONICAL_RUNNERS:
    let info = registry.getOrDefault(name)
    let binary = if info.binary.len > 0: info.binary else: name
    let found = findExe(binary).len > 0
    if found:
      let ver = getVersion(binary)
      let tag = if ver.len > 0: ver else: "found"
      lines.add("  [+] " & align(name, 10) & " (" & binary & ")  " & tag)
    else:
      lines.add("  [-] " & align(name, 10) & " (" & binary & ")  not found")
  return lines.join("\n")

proc helpText*(): string =
  result = HELP_TEXT

proc usageText*(): string =
  result = "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""

proc helpOutput*(): string =
  result = strip(helpText(), leading = false, trailing = true, chars = {'\n'}) & "\n\n" & runnerChecklist()

proc usageOutput*(): string =
  result = usageText() & "\n" & runnerChecklist()

proc printHelp*() =
  echo helpOutput()

proc printUsage*() =
  write stderr, usageOutput() & "\n"
