import std/options
import std/os
import std/strtabs
import std/tables
import call_coding_clis/runner
import call_coding_clis/parser
import call_coding_clis/config
import call_coding_clis/help

type
  CliResult* = object
    exitCode*: int
    stdout*: string
    stderr*: string

proc runCli*(argv: seq[string], configPath: Option[string] = none(string), realOpencode: string = ""): CliResult =
  if argv.len == 0:
    result.exitCode = 1
    result.stderr = usageOutput() & "\n"
    return

  if argv.len == 1 and (argv[0] == "--help" or argv[0] == "-h"):
    result.exitCode = 0
    result.stdout = helpOutput() & "\n"
    return

  let parsed = parseArgs(argv)
  try:
    let cfg = loadConfig(configPath)
    let (finalArgv, env, warnings) = resolveCommand(parsed, some(cfg))

    var spec = CommandSpec(
      argv: finalArgv,
      stdinText: none(string),
      cwd: none(string),
      env: newStringTable()
    )
    for k, v in env:
      spec.env[k] = v

    if realOpencode.len > 0:
      spec.argv[0] = realOpencode

    for warning in warnings:
      result.stderr.add(warning)
      result.stderr.add("\n")

    let runner = newRunner()
    let runResult = runner.run(spec)
    result.stdout.add(runResult.stdout)
    result.stderr.add(runResult.stderr)
    result.exitCode = runResult.exitCode
  except ValueError as exc:
    result.exitCode = 1
    result.stderr = exc.msg & "\n"

proc main() =
  var argv: seq[string] = @[]
  for i in 1..paramCount():
    argv.add(paramStr(i))

  let result = runCli(argv, none(string), getEnv("CCC_REAL_OPENCODE"))
  if result.stdout.len > 0:
    write(stdout, result.stdout)
  if result.stderr.len > 0:
    write(stderr, result.stderr)
  quit(result.exitCode)

when isMainModule:
  main()
