import { basename } from 'node:path'

let stdin = ''

process.stdin.setEncoding('utf8')
process.stdin.on('data', (chunk) => {
  stdin += chunk
})
process.stdin.on('end', () => {
  process.stdout.write(`stdin:${stdin.trim()}\n`)
  process.stdout.write(`cwd:${basename(process.cwd())}\n`)
  process.stdout.write(`env:${process.env.RUN_SHAPE_ENV ?? ''}\n`)
})
