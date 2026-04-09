import test from 'node:test'
import assert from 'node:assert/strict'

import { printHelp, printUsage } from '../src/help.js'

function captureStdout(fn) {
  const original = process.stdout.write
  let output = ''
  process.stdout.write = function (chunk, encoding, callback) {
    output += typeof chunk === 'string' ? chunk : chunk.toString(encoding)
    if (typeof callback === 'function') callback()
    return true
  }
  try {
    fn()
  } finally {
    process.stdout.write = original
  }
  return output
}

function captureStderr(fn) {
  const original = process.stderr.write
  let output = ''
  process.stderr.write = function (chunk, encoding, callback) {
    output += typeof chunk === 'string' ? chunk : chunk.toString(encoding)
    if (typeof callback === 'function') callback()
    return true
  }
  try {
    fn()
  } finally {
    process.stderr.write = original
  }
  return output
}

test('printHelp mentions @name fallback semantics', () => {
  const output = captureStdout(() => printHelp())
  assert.match(output, /ccc \[controls\.\.\.\] "<Prompt>"/)
  assert.match(output, /@name\s+Use a named preset from config; if no preset exists, treat it as an agent/)
  assert.match(output, /ccc cc \+2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"/)
  assert.match(output, /ccc c \+4 :openai:gpt-5\.4-mini @agent "Debug the parser"/)
  assert.match(output, /codex \(c\/cx\), roocode \(rc\)/)
  assert.match(output, /Config:/)
})

test('printUsage prints @name usage to stderr', () => {
  const output = captureStderr(() => printUsage())
  assert.match(output, /usage: ccc \[controls\.\.\.\] "<Prompt>"/)
})
