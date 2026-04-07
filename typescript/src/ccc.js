#!/usr/bin/env node

import { buildPromptSpec, Runner } from './index.js'

const args = process.argv.slice(2)

if (args.length !== 1) {
  console.error('usage: ccc "<Prompt>"')
  process.exit(1)
}

const runnerPrefix = process.env.CCC_REAL_OPENCODE
  ? [process.env.CCC_REAL_OPENCODE, 'run']
  : ['opencode', 'run']

let spec
try {
  spec = buildPromptSpec(args[0], { runnerPrefix })
} catch (err) {
  console.error(err.message)
  process.exit(1)
}

const result = await new Runner().stream(
  spec,
  (channel, chunk) => {
    if (channel === 'stdout') {
      process.stdout.write(chunk)
      return
    }
    process.stderr.write(chunk)
  },
)

process.exit(result.exitCode)
