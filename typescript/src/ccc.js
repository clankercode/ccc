#!/usr/bin/env node

import { Runner } from './index.js'
import { parseArgs, resolveCommand } from './parser.js'
import { loadConfig } from './config.js'
import { printHelp, printUsage } from './help.js'

const args = process.argv.slice(2)

if (args.length === 0) {
  printUsage()
  process.exit(1)
}

if (args.length === 1 && (args[0] === '--help' || args[0] === '-h')) {
  printHelp()
  process.exit(0)
}

let spec
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
