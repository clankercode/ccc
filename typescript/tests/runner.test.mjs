import test from 'node:test'
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { chmodSync } from 'node:fs'
import { spawn, execFile } from 'node:child_process'
import { promisify } from 'node:util'

import { Runner, buildPromptSpec } from '../src/index.js'

const here = dirname(fileURLToPath(import.meta.url))
const shell = '/bin/sh'
const shellScript = (body) => [shell, '-c', body]
const execFileAsync = promisify(execFile)

test('buildPromptSpec maps ccc prompt to opencode run', () => {
  const spec = buildPromptSpec('Fix the failing tests')

  assert.deepEqual(spec.argv, ['opencode', 'run', 'Fix the failing tests'])
})

test('buildPromptSpec supports a runner prefix override', () => {
  const spec = buildPromptSpec('Fix the failing tests', {
    runnerPrefix: ['node', 'runner.mjs'],
  })

  assert.deepEqual(spec.argv, ['node', 'runner.mjs', 'Fix the failing tests'])
})

test('buildPromptSpec rejects empty prompts', () => {
  assert.throws(() => buildPromptSpec('   '))
})

test('Runner.run returns a completed result from injected executor', async () => {
  const runner = new Runner({
    executor: async (spec) => ({
      argv: spec.argv,
      exitCode: 0,
      stdout: 'ok',
      stderr: '',
    }),
  })

  const result = await runner.run({ argv: ['fake', '--json'] })

  assert.deepEqual(result.argv, ['fake', '--json'])
  assert.equal(result.exitCode, 0)
  assert.equal(result.stdout, 'ok')
})

test('Runner.run executes a real subprocess by default', async () => {
  const runner = new Runner()

  const result = await runner.run({
    argv: shellScript("printf 'fixture-ok\\n'"),
  })

  assert.equal(result.exitCode, 0)
  assert.equal(result.stdout.trim(), 'fixture-ok')
})

test('Runner.run reports missing binary startup failure', async () => {
  const runner = new Runner()

  const result = await runner.run({ argv: ['/definitely/missing/runner-binary'] })

  assert.notEqual(result.exitCode, 0)
  assert.equal(result.stdout, '')
  assert.match(result.stderr, /failed to start/)
  assert.match(result.stderr, /runner-binary/)
})

test('Runner.run preserves stdinText, cwd, and env', async () => {
  const runner = new Runner()
  const cwdPath = join(here, 'fixtures')

  const result = await runner.run({
    argv: shellScript(
      "read input; printf 'stdin:%s\\n' \"$input\"; printf 'cwd:%s\\n' \"$(basename \"$PWD\")\"; printf 'env:%s\\n' \"$RUN_SHAPE_ENV\"",
    ),
    stdinText: 'stdin-value',
    cwd: cwdPath,
    env: { RUN_SHAPE_ENV: 'env-value' },
  })

  assert.equal(result.exitCode, 0)
  assert.match(result.stdout, /stdin:stdin-value/)
  assert.match(result.stdout, /cwd:fixtures/)
  assert.match(result.stdout, /env:env-value/)
})

test('Runner.stream emits injected stdout and stderr events', async () => {
  const events = []
  const runner = new Runner({
    streamExecutor: async (spec, onEvent) => {
      onEvent('stdout', 'hello')
      onEvent('stderr', 'warn')
      return {
        argv: spec.argv,
        exitCode: 2,
        stdout: '',
        stderr: '',
      }
    },
  })

  const result = await runner.stream({ argv: ['fake'] }, (channel, chunk) => {
    events.push([channel, chunk])
  })

  assert.deepEqual(events, [
    ['stdout', 'hello'],
    ['stderr', 'warn'],
  ])
  assert.equal(result.exitCode, 2)
})

test('Runner.stream executes a real subprocess and emits output', async () => {
  const runner = new Runner()
  const events = []

  const result = await runner.stream(
    {
      argv: shellScript(
        "read input; printf 'stdout:%s\\n' \"$input\"; printf 'stderr:%s\\n' \"$STREAM_TEST\" >&2",
      ),
      stdinText: 'stdin-value',
      env: { STREAM_TEST: 'env-value' },
    },
    (channel, chunk) => {
      events.push([channel, chunk.trim()])
    },
  )

  assert.equal(result.exitCode, 0)
  assert.deepEqual(events, [
    ['stdout', 'stdout:stdin-value'],
    ['stderr', 'stderr:env-value'],
  ])
})

test('Runner.stream reports missing binary startup failure', async () => {
  const runner = new Runner()
  const events = []

  const result = await runner.stream(
    { argv: ['/definitely/missing/runner-binary'] },
    (channel, chunk) => {
      events.push([channel, chunk])
    },
  )

  assert.notEqual(result.exitCode, 0)
  assert.equal(result.stdout, '')
  assert.match(result.stderr, /failed to start/)
  assert.match(result.stderr, /runner-binary/)
  assert.deepEqual(events, [['stderr', result.stderr]])
})

test('ccc entrypoint exits successfully with a stub runner', async () => {
  const scriptPath = join(here, '..', 'src', 'ccc.js')
  const runnerFixture = join(here, 'fixtures', 'ccc-runner.sh')
  chmodSync(runnerFixture, 0o755)
  await execFileAsync('node', [scriptPath, 'Fix the failing tests'], {
    env: {
      ...process.env,
      PATH: process.env.PATH,
      CCC_CONFIG: '/tmp/ccc-test-missing-config.toml',
      XDG_CONFIG_HOME: '/tmp/ccc-test-xdg-config',
      CCC_REAL_OPENCODE: runnerFixture,
    },
  })
})
