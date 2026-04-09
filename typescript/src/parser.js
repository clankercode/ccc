export class RunnerInfo {
  constructor({ binary, extraArgs = [], thinkingFlags = {}, providerFlag = '', modelFlag = '', agentFlag = '' }) {
    this.binary = binary
    this.extraArgs = extraArgs
    this.thinkingFlags = thinkingFlags
    this.providerFlag = providerFlag
    this.modelFlag = modelFlag
    this.agentFlag = agentFlag
  }
}

export const RUNNER_REGISTRY = {}

function registerDefaults() {
  if (Object.keys(RUNNER_REGISTRY).length) return

  RUNNER_REGISTRY.opencode = new RunnerInfo({
    binary: 'opencode',
    extraArgs: ['run'],
    thinkingFlags: {},
    providerFlag: '',
    modelFlag: '',
    agentFlag: '--agent',
  })
  RUNNER_REGISTRY.claude = new RunnerInfo({
    binary: 'claude',
    extraArgs: [],
    thinkingFlags: {
      0: ['--thinking', 'disabled'],
      1: ['--thinking', 'enabled', '--effort', 'low'],
      2: ['--thinking', 'enabled', '--effort', 'medium'],
      3: ['--thinking', 'enabled', '--effort', 'high'],
      4: ['--thinking', 'enabled', '--effort', 'max'],
    },
    providerFlag: '',
    modelFlag: '--model',
    agentFlag: '--agent',
  })
  RUNNER_REGISTRY.kimi = new RunnerInfo({
    binary: 'kimi',
    extraArgs: [],
    thinkingFlags: {
      0: ['--no-thinking'],
      1: ['--thinking'],
      2: ['--thinking'],
      3: ['--thinking'],
      4: ['--thinking'],
    },
    providerFlag: '',
    modelFlag: '--model',
    agentFlag: '--agent',
  })
  RUNNER_REGISTRY.codex = new RunnerInfo({
    binary: 'codex',
    extraArgs: [],
    thinkingFlags: {},
    providerFlag: '',
    modelFlag: '--model',
  })
  RUNNER_REGISTRY.roocode = new RunnerInfo({
    binary: 'roocode',
    extraArgs: [],
    thinkingFlags: {},
    providerFlag: '',
    modelFlag: '',
  })
  RUNNER_REGISTRY.crush = new RunnerInfo({
    binary: 'crush',
    extraArgs: [],
    thinkingFlags: {},
    providerFlag: '',
    modelFlag: '',
  })

  RUNNER_REGISTRY.oc = RUNNER_REGISTRY.opencode
  RUNNER_REGISTRY.cc = RUNNER_REGISTRY.claude
  RUNNER_REGISTRY.c = RUNNER_REGISTRY.codex
  RUNNER_REGISTRY.cx = RUNNER_REGISTRY.codex
  RUNNER_REGISTRY.k = RUNNER_REGISTRY.kimi
  RUNNER_REGISTRY.rc = RUNNER_REGISTRY.roocode
  RUNNER_REGISTRY.cr = RUNNER_REGISTRY.crush
}

registerDefaults()

const RUNNER_SELECTOR_RE = /^(?:oc|cc|c|cx|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$/i
const THINKING_RE = /^\+([0-4])$/
const PROVIDER_MODEL_RE = /^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$/
const MODEL_RE = /^:([a-zA-Z0-9._-]+)$/
const ALIAS_RE = /^@([a-zA-Z0-9_-]+)$/

export function parseArgs(argv) {
  const parsed = { runner: null, thinking: null, provider: null, model: null, alias: null, prompt: '' }
  const positional = []

  for (const token of argv) {
    if (RUNNER_SELECTOR_RE.test(token) && parsed.runner === null && positional.length === 0) {
      parsed.runner = token.toLowerCase()
    } else if (THINKING_RE.test(token) && positional.length === 0) {
      parsed.thinking = parseInt(token.slice(1), 10)
    } else if (PROVIDER_MODEL_RE.test(token) && positional.length === 0) {
      const m = PROVIDER_MODEL_RE.exec(token)
      parsed.provider = m[1]
      parsed.model = m[2]
    } else if (MODEL_RE.test(token) && positional.length === 0) {
      const m = MODEL_RE.exec(token)
      parsed.model = m[1]
    } else if (ALIAS_RE.test(token) && parsed.alias === null && positional.length === 0) {
      const m = ALIAS_RE.exec(token)
      parsed.alias = m[1]
    } else {
      positional.push(token)
    }
  }

  parsed.prompt = positional.join(' ')
  return parsed
}

function resolveRunnerName(name, config) {
  if (name === null || name === undefined) {
    return config.defaultRunner
  }
  const abbrev = config.abbreviations[name]
  if (abbrev) return abbrev
  return name
}

export function resolveCommand(parsed, config) {
  if (!config) {
    config = {
      defaultRunner: 'oc',
      defaultProvider: '',
      defaultModel: '',
      defaultThinking: null,
      aliases: {},
      abbreviations: {},
    }
  }

  const warnings = []
  let runnerName = resolveRunnerName(parsed.runner, config)
  let info = RUNNER_REGISTRY[runnerName] || RUNNER_REGISTRY[config.defaultRunner] || RUNNER_REGISTRY.opencode

  let aliasDef = null
  if (parsed.alias && config.aliases[parsed.alias]) {
    aliasDef = config.aliases[parsed.alias]
  }

  if (aliasDef && aliasDef.runner && parsed.runner === null) {
    runnerName = resolveRunnerName(aliasDef.runner, config)
    info = RUNNER_REGISTRY[runnerName] || info
  }

  const argv = [info.binary, ...info.extraArgs]

  let effectiveThinking = parsed.thinking
  if (effectiveThinking === null && aliasDef && aliasDef.thinking !== null && aliasDef.thinking !== undefined) {
    effectiveThinking = aliasDef.thinking
  }
  if (effectiveThinking === null || effectiveThinking === undefined) {
    effectiveThinking = config.defaultThinking
  }
  if (effectiveThinking !== null && effectiveThinking !== undefined && effectiveThinking in info.thinkingFlags) {
    argv.push(...info.thinkingFlags[effectiveThinking])
  }

  let effectiveProvider = parsed.provider
  if (effectiveProvider === null && aliasDef && aliasDef.provider) {
    effectiveProvider = aliasDef.provider
  }
  if (effectiveProvider === null) {
    effectiveProvider = config.defaultProvider || null
  }

  let effectiveModel = parsed.model
  if (effectiveModel === null && aliasDef && aliasDef.model) {
    effectiveModel = aliasDef.model
  }
  if (effectiveModel === null) {
    effectiveModel = config.defaultModel || null
  }

  if (effectiveModel && info.modelFlag) {
    argv.push(info.modelFlag, effectiveModel)
  }

  let effectiveAgent = null
  if (parsed.alias && !aliasDef) {
    effectiveAgent = parsed.alias
  }
  if (effectiveAgent === null && aliasDef && aliasDef.agent) {
    effectiveAgent = aliasDef.agent
  }
  if (effectiveAgent) {
    if (info.agentFlag) {
      argv.push(info.agentFlag, effectiveAgent)
    } else {
      warnings.push(
        `warning: runner "${runnerName}" does not support agents; ignoring @${effectiveAgent}`,
      )
    }
  }

  const envOverrides = {}
  if (effectiveProvider) {
    envOverrides.CCC_PROVIDER = effectiveProvider
  }

  const prompt = parsed.prompt.trim()
  if (!prompt) {
    throw new Error('prompt must not be empty')
  }

  argv.push(prompt)
  return { argv, env: envOverrides, warnings }
}
