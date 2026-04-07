import test from 'node:test'
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { spawn } from 'node:child_process'

import { Runner, buildPromptSpec } from '../src/index.js'

const here = dirname(fileURLToPath(import.meta.url))

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
  const scriptPath = join(here, 'fixtures', 'echo.mjs')

  const result = await runner.run({ argv: ['node', scriptPath] })

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
  const scriptPath = join(here, 'fixtures', 'run-shape.mjs')
  const cwdPath = join(here, 'fixtures')

  const result = await runner.run({
    argv: ['node', scriptPath],
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
  const scriptPath = join(here, 'fixtures', 'stream.mjs')
  const events = []

  const result = await runner.stream(
    {
      argv: ['node', scriptPath],
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

test('ccc entrypoint forwards streamed stdout and stderr', async () => {
  const scriptPath = join(here, '..', 'src', 'ccc.js')
  const runnerFixture = join(here, 'fixtures', 'ccc-runner.mjs')
  const child = spawn('node', [scriptPath, 'Fix the failing tests'], {
    env: {
      ...process.env,
      PATH: process.env.PATH,
      CCC_RUNNER_PREFIX_JSON: JSON.stringify(['node', runnerFixture]),
    },
  })

  let stdout = ''
  let stderr = ''

  child.stdout.on('data', (chunk) => {
    stdout += chunk.toString()
  })
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString()
  })

  const exitCode = await new Promise((resolve, reject) => {
    child.on('error', reject)
    child.on('close', resolve)
  })

  assert.equal(exitCode, 0)
  assert.equal(stderr.trim(), 'ccc-stderr:Fix the failing tests')
  assert.equal(stdout.trim(), 'ccc-stdout:Fix the failing tests')
})
