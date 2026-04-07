const prompt = process.argv[2] ?? ''

process.stdout.write(`ccc-stdout:${prompt}\n`)
process.stderr.write(`ccc-stderr:${prompt}\n`)
