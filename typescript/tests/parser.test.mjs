import test from 'node:test'
import assert from 'node:assert/strict'
import { writeFileSync, unlinkSync } from 'node:fs'

import { parseArgs, resolveCommand, RUNNER_REGISTRY } from '../src/parser.js'
import { loadConfig } from '../src/config.js'

test('parseArgs: prompt-only', () => {
  const parsed = parseArgs(['fix the bug'])
  assert.deepEqual(parsed, {
    runner: null,
    thinking: null,
    provider: null,
    model: null,
    alias: null,
    prompt: 'fix the bug',
  })
})

test('parseArgs: runner selector', () => {
  const parsed = parseArgs(['claude', 'do the thing'])
  assert.equal(parsed.runner, 'claude')
  assert.equal(parsed.prompt, 'do the thing')
})

test('parseArgs: runner abbreviation cc', () => {
  const parsed = parseArgs(['cc', 'prompt'])
  assert.equal(parsed.runner, 'cc')
})

test('parseArgs: runner abbreviation oc', () => {
  const parsed = parseArgs(['oc', 'prompt'])
  assert.equal(parsed.runner, 'oc')
})

test('parseArgs: runner abbreviation k', () => {
  const parsed = parseArgs(['k', 'prompt'])
  assert.equal(parsed.runner, 'k')
})

test('parseArgs: runner abbreviation rc', () => {
  const parsed = parseArgs(['rc', 'prompt'])
  assert.equal(parsed.runner, 'rc')
})

test('parseArgs: runner abbreviation cr', () => {
  const parsed = parseArgs(['cr', 'prompt'])
  assert.equal(parsed.runner, 'cr')
})

test('parseArgs: thinking flag', () => {
  const parsed = parseArgs(['+3', 'prompt'])
  assert.equal(parsed.thinking, 3)
  assert.equal(parsed.prompt, 'prompt')
})

test('parseArgs: thinking flag zero', () => {
  const parsed = parseArgs(['+0', 'prompt'])
  assert.equal(parsed.thinking, 0)
})

test('parseArgs: provider:model', () => {
  const parsed = parseArgs([':openai:gpt-4o', 'prompt'])
  assert.equal(parsed.provider, 'openai')
  assert.equal(parsed.model, 'gpt-4o')
})

test('parseArgs: model only', () => {
  const parsed = parseArgs([':gpt-4o', 'prompt'])
  assert.equal(parsed.model, 'gpt-4o')
  assert.equal(parsed.provider, null)
})

test('parseArgs: alias', () => {
  const parsed = parseArgs(['@work', 'prompt'])
  assert.equal(parsed.alias, 'work')
})

test('parseArgs: full combo', () => {
  const parsed = parseArgs(['claude', '+2', ':anthropic:sonnet', '@fast', 'fix it'])
  assert.equal(parsed.runner, 'claude')
  assert.equal(parsed.thinking, 2)
  assert.equal(parsed.provider, 'anthropic')
  assert.equal(parsed.model, 'sonnet')
  assert.equal(parsed.alias, 'fast')
  assert.equal(parsed.prompt, 'fix it')
})

test('parseArgs: multi-word prompt', () => {
  const parsed = parseArgs(['fix', 'all', 'the', 'bugs'])
  assert.equal(parsed.prompt, 'fix all the bugs')
})

test('parseArgs: runner after positional becomes positional', () => {
  const parsed = parseArgs(['hello', 'claude'])
  assert.equal(parsed.runner, null)
  assert.equal(parsed.prompt, 'hello claude')
})

test('parseArgs: alias after positional is positional', () => {
  const parsed = parseArgs(['hello', '@work'])
  assert.equal(parsed.alias, null)
  assert.equal(parsed.prompt, 'hello @work')
})

test('resolveCommand: default runner (opencode)', () => {
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: null, prompt: 'do stuff' })
  assert.deepEqual(result.argv[0], 'opencode')
  assert.equal(result.argv[result.argv.length - 1], 'do stuff')
})

test('resolveCommand: claude runner', () => {
  const result = resolveCommand({ runner: 'claude', thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' })
  assert.equal(result.argv[0], 'claude')
})

test('resolveCommand: thinking flags for claude +2', () => {
  const result = resolveCommand({ runner: 'claude', thinking: 2, provider: null, model: null, alias: null, prompt: 'prompt' })
  assert.deepEqual(result.argv.slice(1, 3), ['--thinking', 'medium'])
})

test('resolveCommand: thinking flags for claude +0', () => {
  const result = resolveCommand({ runner: 'claude', thinking: 0, provider: null, model: null, alias: null, prompt: 'prompt' })
  assert.deepEqual(result.argv.slice(1, 2), ['--no-thinking'])
})

test('resolveCommand: thinking flags for kimi +3', () => {
  const result = resolveCommand({ runner: 'kimi', thinking: 3, provider: null, model: null, alias: null, prompt: 'prompt' })
  assert.deepEqual(result.argv.slice(1, 3), ['--think', 'high'])
})

test('resolveCommand: model flag for claude', () => {
  const result = resolveCommand({ runner: 'claude', thinking: null, provider: null, model: 'sonnet', alias: null, prompt: 'prompt' })
  assert.ok(result.argv.includes('--model'))
  assert.ok(result.argv.includes('sonnet'))
})

test('resolveCommand: provider env override', () => {
  const result = resolveCommand({ runner: null, thinking: null, provider: 'openai', model: null, alias: null, prompt: 'prompt' })
  assert.equal(result.env.CCC_PROVIDER, 'openai')
})

test('resolveCommand: no provider env when empty', () => {
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' })
  assert.deepEqual(result.env, {})
})

test('resolveCommand: empty prompt throws', () => {
  assert.throws(
    () => resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: null, prompt: '   ' }),
    { message: 'prompt must not be empty' },
  )
})

test('resolveCommand: config default runner', () => {
  const config = {
    defaultRunner: 'claude',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: null,
    aliases: {},
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' }, config)
  assert.equal(result.argv[0], 'claude')
})

test('resolveCommand: config default thinking', () => {
  const config = {
    defaultRunner: 'claude',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: 1,
    aliases: {},
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' }, config)
  assert.ok(result.argv.includes('--thinking'))
  assert.ok(result.argv.includes('low'))
})

test('resolveCommand: config default model', () => {
  const config = {
    defaultRunner: 'claude',
    defaultProvider: '',
    defaultModel: 'sonnet',
    defaultThinking: null,
    aliases: {},
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' }, config)
  assert.ok(result.argv.includes('--model'))
  assert.ok(result.argv.includes('sonnet'))
})

test('resolveCommand: config default provider', () => {
  const config = {
    defaultRunner: 'oc',
    defaultProvider: 'openai',
    defaultModel: '',
    defaultThinking: null,
    aliases: {},
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' }, config)
  assert.equal(result.env.CCC_PROVIDER, 'openai')
})

test('resolveCommand: alias resolution', () => {
  const config = {
    defaultRunner: 'oc',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: null,
    aliases: {
      fast: { runner: 'claude', model: 'sonnet' },
    },
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: 'fast', prompt: 'prompt' }, config)
  assert.equal(result.argv[0], 'claude')
  assert.ok(result.argv.includes('sonnet'))
  assert.deepEqual(result.warnings, [])
})

test('resolveCommand: alias thinking override', () => {
  const config = {
    defaultRunner: 'claude',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: null,
    aliases: {
      deep: { thinking: 4 },
    },
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: 'deep', prompt: 'prompt' }, config)
  assert.ok(result.argv.includes('--thinking'))
  assert.ok(result.argv.includes('max'))
  assert.deepEqual(result.warnings, [])
})

test('resolveCommand: alias fallback uses agent when preset missing', () => {
  const result = resolveCommand(
    { runner: null, thinking: null, provider: null, model: null, alias: 'reviewer', prompt: 'prompt' },
    {
      defaultRunner: 'oc',
      defaultProvider: '',
      defaultModel: '',
      defaultThinking: null,
      aliases: {},
      abbreviations: {},
    },
  )
  assert.deepEqual(result.argv.slice(0, 4), ['opencode', 'run', '--agent', 'reviewer'])
  assert.deepEqual(result.warnings, [])
})

test('resolveCommand: preset agent is emitted when configured', () => {
  const config = {
    defaultRunner: 'oc',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: null,
    aliases: {
      review: { agent: 'specialist' },
    },
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: null, provider: null, model: null, alias: 'review', prompt: 'prompt' }, config)
  assert.deepEqual(result.argv.slice(0, 4), ['opencode', 'run', '--agent', 'specialist'])
  assert.deepEqual(result.warnings, [])
})

test('resolveCommand: unsupported agent emits warning and no agent flag', () => {
  const result = resolveCommand(
    { runner: 'rc', thinking: null, provider: null, model: null, alias: 'reviewer', prompt: 'prompt' },
    {
      defaultRunner: 'oc',
      defaultProvider: '',
      defaultModel: '',
      defaultThinking: null,
      aliases: {},
      abbreviations: {},
    },
  )
  assert.equal(result.argv[0], 'codex')
  assert.ok(!result.argv.includes('--agent'))
  assert.deepEqual(result.warnings, ['warning: runner "rc" does not support agents; ignoring @reviewer'])
})

test('resolveCommand: abbreviation resolution', () => {
  const config = {
    defaultRunner: 'oc',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: null,
    aliases: {},
    abbreviations: { myrunner: 'claude' },
  }
  const result = resolveCommand({ runner: 'myrunner', thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' }, config)
  assert.equal(result.argv[0], 'claude')
})

test('resolveCommand: unknown runner falls back to default', () => {
  const result = resolveCommand({ runner: 'unknown', thinking: null, provider: null, model: null, alias: null, prompt: 'prompt' })
  assert.equal(result.argv[0], 'opencode')
})

test('resolveCommand: parsed thinking overrides alias thinking', () => {
  const config = {
    defaultRunner: 'claude',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: null,
    aliases: {
      deep: { thinking: 4 },
    },
    abbreviations: {},
  }
  const result = resolveCommand({ runner: null, thinking: 1, provider: null, model: null, alias: 'deep', prompt: 'prompt' }, config)
  assert.ok(result.argv.includes('low'))
})

test('RUNNER_REGISTRY: has all expected runners', () => {
  assert.ok(RUNNER_REGISTRY.opencode)
  assert.ok(RUNNER_REGISTRY.claude)
  assert.ok(RUNNER_REGISTRY.kimi)
  assert.ok(RUNNER_REGISTRY.codex)
  assert.ok(RUNNER_REGISTRY.crush)
})

test('RUNNER_REGISTRY: agent flags for supported runners', () => {
  assert.equal(RUNNER_REGISTRY.opencode.agentFlag, '--agent')
  assert.equal(RUNNER_REGISTRY.claude.agentFlag, '--agent')
  assert.equal(RUNNER_REGISTRY.kimi.agentFlag, '--agent')
  assert.equal(RUNNER_REGISTRY.codex.agentFlag, '')
  assert.equal(RUNNER_REGISTRY.crush.agentFlag, '')
})

test('RUNNER_REGISTRY: abbreviations point to same objects', () => {
  assert.equal(RUNNER_REGISTRY.oc, RUNNER_REGISTRY.opencode)
  assert.equal(RUNNER_REGISTRY.cc, RUNNER_REGISTRY.claude)
  assert.equal(RUNNER_REGISTRY.c, RUNNER_REGISTRY.claude)
  assert.equal(RUNNER_REGISTRY.k, RUNNER_REGISTRY.kimi)
  assert.equal(RUNNER_REGISTRY.rc, RUNNER_REGISTRY.codex)
  assert.equal(RUNNER_REGISTRY.cr, RUNNER_REGISTRY.crush)
})

test('loadConfig: returns defaults when no file', () => {
  const config = loadConfig('/nonexistent/path/config.toml')
  assert.equal(config.defaultRunner, 'oc')
  assert.equal(config.defaultProvider, '')
  assert.equal(config.defaultModel, '')
  assert.equal(config.defaultThinking, null)
  assert.deepEqual(config.aliases, {})
  assert.deepEqual(config.abbreviations, {})
})

test('loadConfig: parses agent in alias presets', () => {
  const configToml = `
[aliases.review]
runner = "claude"
thinking = 2
  provider = "anthropic"
  model = "sonnet"
  agent = "specialist"
`
  const path = `/tmp/ccc-typescript-agent-config-${process.pid}.toml`
  writeFileSync(path, configToml)
  try {
    const config = loadConfig(path)
    assert.equal(config.aliases.review.agent, 'specialist')
    assert.equal(config.aliases.review.runner, 'claude')
  } finally {
    unlinkSync(path)
  }
})
