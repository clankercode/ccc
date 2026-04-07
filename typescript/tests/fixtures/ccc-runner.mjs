#!/usr/bin/env node
if (process.argv[2] === 'run') {
  process.argv.splice(2, 1)
}
const prompt = process.argv[2] ?? ''

process.stdout.write(`ccc-stdout:${prompt}\n`)
process.stderr.write(`ccc-stderr:${prompt}\n`)
