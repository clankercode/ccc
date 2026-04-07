import { spawn } from 'node:child_process'

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
  return runChildProcess(spec, () => {})
}

export class Runner {
  constructor(options = {}) {
    this.executor = options.executor ?? defaultExecutor
    this.streamExecutor = options.streamExecutor ?? runChildProcess
  }

  async run(spec) {
    return this.executor(spec)
  }

  async stream(spec, onEvent) {
    return this.streamExecutor(spec, onEvent)
  }
}

async function runChildProcess(spec, onEvent) {
  return new Promise((resolve, reject) => {
    const [command, ...args] = spec.argv
    const child = spawn(command, args, {
      cwd: spec.cwd,
      env: spec.env ? { ...process.env, ...spec.env } : process.env,
      stdio: 'pipe',
    })

    let stdout = ''
    let stderr = ''

    child.stdout.on('data', (chunk) => {
      const text = chunk.toString()
      stdout += text
      onEvent('stdout', text)
    })
    child.stderr.on('data', (chunk) => {
      const text = chunk.toString()
      stderr += text
      onEvent('stderr', text)
    })
    child.on('error', reject)
    child.on('close', (code) => {
      resolve({
        argv: spec.argv,
        exitCode: code ?? 1,
        stdout,
        stderr,
      })
    })

    if (spec.stdinText) {
      child.stdin.write(spec.stdinText)
    }
    child.stdin.end()
  })
}
