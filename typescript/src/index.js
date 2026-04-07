export function buildPromptSpec(prompt) {
  const normalizedPrompt = prompt.trim()
  if (!normalizedPrompt) {
    throw new Error('prompt must not be empty')
  }

  return {
    argv: ['opencode', 'run', normalizedPrompt],
  }
}

async function defaultExecutor(spec) {
  return {
    argv: spec.argv,
    exitCode: 0,
    stdout: '',
    stderr: '',
  }
}

export class Runner {
  constructor(options = {}) {
    this.executor = options.executor ?? defaultExecutor
  }

  async run(spec) {
    return this.executor(spec)
  }
}
