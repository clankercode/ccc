import test from 'node:test'
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

import { Runner, buildPromptSpec } from '../src/index.js'

const here = dirname(fileURLToPath(import.meta.url))

test('buildPromptSpec maps ccc prompt to opencode run', () => {
  const spec = buildPromptSpec('Fix the failing tests')

  assert.deepEqual(spec.argv, ['opencode', 'run', 'Fix the failing tests'])
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
