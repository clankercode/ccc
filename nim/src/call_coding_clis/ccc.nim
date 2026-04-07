import std/os
import call_coding_clis/runner
import call_coding_clis/prompt_spec

proc main() =
  if paramCount() != 1:
    write(stderr, "usage: ccc \"<Prompt>\"\n")
    quit(1)

  let prompt = paramStr(1)

  var spec: CommandSpec
  try:
    spec = buildPromptSpec(prompt)
  except ValueError as e:
    write(stderr, e.msg & "\n")
    quit(1)

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
