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
      stdout += chunk.toString()
    })
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString()
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

export class Runner {
  constructor(options = {}) {
    this.executor = options.executor ?? defaultExecutor
  }

  async run(spec) {
    return this.executor(spec)
  }
}
