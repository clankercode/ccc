import std/options
import std/os
import std/unittest
import call_coding_clis/ccc

const PROMPT = "Fix the failing tests"

proc writeStubRunner(path: string) =
  writeFile(
    path,
    """#!/bin/sh
printf '%s' "$1"
shift
for arg in "$@"; do
  printf ' %s' "$arg"
done
printf '\n'
"""
  )
  setFilePermissions(
    path,
    {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec},
  )

proc writePresetConfig(path: string) =
  writeFile(path, "[aliases.reviewer]\nagent = \"specialist\"\n")

suite "cli":
  test "fallback agent uses opencode flag":
    let stubPath = getTempDir() / "ccc-nim-cli-opencode"
    writeStubRunner(stubPath)
    let result = runCli(@["@reviewer", PROMPT], none(string), stubPath)
    check result.exitCode == 0
    check result.stdout == "run --agent reviewer Fix the failing tests\n"
    check result.stderr == ""

  test "preset agent wins":
    let stubPath = getTempDir() / "ccc-nim-cli-opencode"
    let configPath = getTempDir() / "ccc-nim-cli-config.toml"
    writeStubRunner(stubPath)
    writePresetConfig(configPath)
    let result = runCli(@["@reviewer", PROMPT], some(configPath), stubPath)
    check result.exitCode == 0
    check result.stdout == "run --agent specialist Fix the failing tests\n"
    check result.stderr == ""

  test "unsupported runner warns and ignores agent":
    let stubPath = getTempDir() / "ccc-nim-cli-opencode"
    let configPath = getTempDir() / "ccc-nim-cli-config.toml"
    writeStubRunner(stubPath)
    writePresetConfig(configPath)
    let result = runCli(@["codex", "@reviewer", PROMPT], some(configPath), stubPath)
    check result.exitCode == 0
    check result.stdout == "Fix the failing tests\n"
    check result.stderr == "warning: runner \"codex\" does not support agents; ignoring @specialist\n"
