import test from 'node:test'
import assert from 'node:assert/strict'

import { Runner, buildPromptSpec } from '../src/index.js'

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
