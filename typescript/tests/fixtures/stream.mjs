let stdin = ''

process.stdin.setEncoding('utf8')
process.stdin.on('data', (chunk) => {
  stdin += chunk
})
process.stdin.on('end', () => {
  process.stdout.write(`stdout:${stdin.trim()}\n`)
  process.stderr.write(`stderr:${process.env.STREAM_TEST ?? ''}\n`)
})
