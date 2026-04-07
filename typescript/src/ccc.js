#!/usr/bin/env node

import { buildPromptSpec, Runner } from './index.js'

const args = process.argv.slice(2)

if (args.length !== 1) {
  console.error('usage: ccc "<Prompt>"')
  process.exit(1)
}

const result = await new Runner().run(buildPromptSpec(args[0]))
if (result.stdout) {
  process.stdout.write(result.stdout)
}
if (result.stderr) {
  process.stderr.write(result.stderr)
}
process.exit(result.exitCode)
