import std/options
import std/os
import std/osproc
import std/streams
import std/strtabs

type
  CommandSpec* = object
    argv*: seq[string]
    stdinText*: Option[string]
    cwd*: Option[string]
    env*: StringTableRef

  CompletedRun* = object
    argv*: seq[string]
    exitCode*: int
    stdout*: string
    stderr*: string

  StreamCallback* = proc(channel: string, data: string) {.closure.}

  RunExecutor* = proc(spec: CommandSpec): CompletedRun {.closure.}

  Runner* = object
    executor*: RunExecutor

proc defaultRun(spec: CommandSpec): CompletedRun =
  let workingDir = if spec.cwd.isSome(): spec.cwd.get() else: ""

  var envTable: StringTableRef = nil
  if spec.env != nil and spec.env.len > 0:
    envTable = newStringTable()
    for k, v in envPairs():
      envTable[k] = v
    for k, v in spec.env:
      envTable[k] = v

  try:
    var p = startProcess(
      command = spec.argv[0],
      workingDir = workingDir,
      args = spec.argv[1 ..^ 1],
      env = envTable,
      options = {poUsePath}
    )

    if spec.stdinText.isSome() and spec.stdinText.get().len > 0:
      let inp = p.inputStream()
      inp.write(spec.stdinText.get())
      inp.flush()
      close(inp)

    let outStrm = p.outputStream()
    let errStrm = p.errorStream()

    let stdoutData = outStrm.readAll()
    let stderrData = errStrm.readAll()

    let rawExit = p.waitForExit()
    let exitCode = if rawExit > 128: 1 else: rawExit

    p.close()

    result = CompletedRun(
      argv: spec.argv,
      exitCode: exitCode,
      stdout: stdoutData,
      stderr: stderrData
    )
  except OSError as e:
    result = CompletedRun(
      argv: spec.argv,
      exitCode: 1,
      stdout: "",
      stderr: "failed to start " & spec.argv[0] & ": " & e.msg & "\n"
    )

proc newRunner*(): Runner =
  result = Runner(executor: defaultRun)

proc run*(self: Runner; spec: CommandSpec): CompletedRun =
  return self.executor(spec)

proc stream*(self: Runner; spec: CommandSpec; onEvent: StreamCallback): CompletedRun =
  let res = self.run(spec)
  if res.stdout.len > 0:
    onEvent("stdout", res.stdout)
  if res.stderr.len > 0:
    onEvent("stderr", res.stderr)
  return res
