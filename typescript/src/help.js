import { execSync, execFileSync } from 'node:child_process'
import { RUNNER_REGISTRY } from './parser.js'

const CANONICAL_RUNNERS = [
  ['opencode', 'oc'],
  ['claude', 'cc'],
  ['kimi', 'k'],
  ['codex', 'c/cx'],
  ['roocode', 'rc'],
  ['crush', 'cr'],
]

const HELP_TEXT = `ccc — call coding CLIs

Usage:
  ccc [controls...] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer "Add tests"
  ccc c +4 :openai:gpt-5.4-mini @agent "Debug the parser"
  ccc k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations
`

function getVersion(binary) {
  try {
    const out = execFileSync(binary, ['--version'], {
      timeout: 3000,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    })
    return out.trim().split('\n')[0]
  } catch {
    return ''
  }
}

function runnerChecklist() {
  const lines = ['Runners:']
  for (const [name, alias] of CANONICAL_RUNNERS) {
    const info = RUNNER_REGISTRY[name]
    const binary = info ? info.binary : name
    let found = false
    try {
      execSync(`which ${binary}`, { stdio: 'pipe' })
      found = true
    } catch {
      found = false
    }
    if (found) {
      const version = getVersion(binary)
      const tag = version || 'found'
      lines.push(`  [+] ${name.padEnd(10)} (${binary})  ${tag}`)
    } else {
      lines.push(`  [-] ${name.padEnd(10)} (${binary})  not found`)
    }
  }
  return lines.join('\n')
}

export function printHelp() {
  process.stdout.write(HELP_TEXT + '\n' + runnerChecklist() + '\n')
}

export function printUsage() {
  process.stderr.write('usage: ccc [controls...] "<Prompt>"\n')
  process.stderr.write(runnerChecklist() + '\n')
}
