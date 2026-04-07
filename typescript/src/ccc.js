#!/usr/bin/env node

import { buildPromptSpec, Runner } from './index.js'
import { parseArgs, resolveCommand } from './parser.js'
import { loadConfig } from './config.js'

const args = process.argv.slice(2)

if (args.length === 0) {
  console.error('usage: ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"')
  process.exit(1)
}

let spec
if (args.length === 1) {
  try {
    spec = buildPromptSpec(args[0])
  } catch (err) {
    console.error(err.message)
    process.exit(1)
  }
} else {
  const parsed = parseArgs(args)
  if (!parsed.prompt.trim()) {
    console.error('prompt must not be empty')
    process.exit(1)
  }
  const config = loadConfig()
  try {
    const resolved = resolveCommand(parsed, config)
    spec = { argv: resolved.argv, env: resolved.env }
  } catch (err) {
    console.error(err.message)
    process.exit(1)
  }
}

const realOpencode = process.env.CCC_REAL_OPENCODE
if (realOpencode) {
  spec.argv[0] = realOpencode
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
