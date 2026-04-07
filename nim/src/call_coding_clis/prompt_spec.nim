import std/strutils
import std/options
import std/strtabs
import call_coding_clis/runner

proc buildPromptSpec*(prompt: string): CommandSpec =
  let trimmed = prompt.strip()
  if trimmed.len == 0:
    raise newException(ValueError, "prompt must not be empty")
  result = CommandSpec(
    argv: @["opencode", "run", trimmed],
    stdinText: none(string),
    cwd: none(string),
    env: newStringTable()
  )
