import std/options
import std/os
import std/strtabs
import std/tables
import call_coding_clis/runner
import call_coding_clis/parser
import call_coding_clis/config

proc main() =
  if paramCount() == 0:
    write(stderr, "usage: ccc [runner] [+thinking] [:provider:model] [@alias] <prompt>\n")
    quit(1)

  var argv: seq[string] = @[]
  for i in 1..paramCount():
    argv.add(paramStr(i))

  let parsed = parseArgs(argv)
  let cfg = loadConfig(none(string))

  let (finalArgv, env) = resolveCommand(parsed, some(cfg))

  var spec = CommandSpec(
    argv: finalArgv,
    stdinText: none(string),
    cwd: none(string),
    env: newStringTable()
  )
  for k, v in env:
    spec.env[k] = v

  let realOpencode = getEnv("CCC_REAL_OPENCODE")
  if realOpencode.len > 0:
    spec.argv[0] = realOpencode

  let runner = newRunner()
  let result = runner.run(spec)

  if result.stdout.len > 0:
    write(stdout, result.stdout)
  if result.stderr.len > 0:
    write(stderr, result.stderr)
  quit(result.exitCode)

when isMainModule:
  main()
