import std/unittest
import std/options
import std/strtabs
import std/strutils
import call_coding_clis/prompt_spec
import call_coding_clis/runner

suite "build prompt spec":
  test "valid prompt":
    let spec = buildPromptSpec("hello")
    check spec.argv == @["opencode", "run", "hello"]

  test "trims whitespace":
    let spec = buildPromptSpec("  foo  ")
    check spec.argv == @["opencode", "run", "foo"]

  test "trims tabs and newlines":
    let spec = buildPromptSpec("\t\nhello\n\t")
    check spec.argv == @["opencode", "run", "hello"]

  test "rejects empty string":
    expect ValueError:
      discard buildPromptSpec("")

  test "rejects whitespace only":
    expect ValueError:
      discard buildPromptSpec("   \t\n  ")

  test "error message is correct":
    try:
      discard buildPromptSpec("")
      check false
    except ValueError as e:
      check e.msg == "prompt must not be empty"

suite "runner":
  test "run captures exit code 0":
    let spec = CommandSpec(
      argv: @["true"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let runner = newRunner()
    let result = runner.run(spec)
    check result.exitCode == 0

  test "run captures stdout":
    let spec = CommandSpec(
      argv: @["echo", "hello"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let runner = newRunner()
    let result = runner.run(spec)
    check result.stdout.strip() == "hello"

  test "run captures nonzero exit code":
    let spec = CommandSpec(
      argv: @["false"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let runner = newRunner()
    let result = runner.run(spec)
    check result.exitCode != 0

  test "run handles startup failure":
    let spec = CommandSpec(
      argv: @["nonexistent_binary_xyz_123"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let runner = newRunner()
    let result = runner.run(spec)
    check result.exitCode == 1
    check "failed to start nonexistent_binary_xyz_123" in result.stderr

  test "stream invokes callbacks":
    let spec = CommandSpec(
      argv: @["echo", "streamtest"],
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    let runner = newRunner()
    var gotStdout = ""
    var gotStderr = ""
    let result = runner.stream(spec, proc(channel: string, data: string) =
      if channel == "stdout":
        gotStdout = data
      elif channel == "stderr":
        gotStderr = data
    )
    check result.exitCode == 0
    check "streamtest" in gotStdout
    check gotStderr == ""
