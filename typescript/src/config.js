import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const CONFIG_DIR_NAME = 'ccc'
const CONFIG_FILE_NAME = 'config.toml'

function defaultConfigPaths() {
  const paths = []
  const xdg = process.env.XDG_CONFIG_HOME
  if (xdg) {
    paths.push(join(xdg, CONFIG_DIR_NAME, CONFIG_FILE_NAME))
  }
  paths.push(join(homedir(), '.config', CONFIG_DIR_NAME, CONFIG_FILE_NAME))
  return paths
}

export function loadConfig(path) {
  const config = {
    defaultRunner: 'oc',
    defaultProvider: '',
    defaultModel: '',
    defaultThinking: null,
    aliases: {},
    abbreviations: {},
  }

  let configPath
  if (path !== null && path !== undefined) {
    configPath = path
  } else {
    for (const candidate of defaultConfigPaths()) {
      try {
        readFileSync(candidate, 'utf-8')
        configPath = candidate
        break
      } catch {
        continue
      }
    }
  }

  if (!configPath) return config

  let content
  try {
    content = readFileSync(configPath, 'utf-8')
  } catch {
    return config
  }

  parseTomlConfig(content, config)
  return config
}

function parseTomlConfig(content, config) {
  let currentSection = ''

  for (const rawLine of content.split('\n')) {
    const trimmed = rawLine.trim()

    if (trimmed === '' || trimmed.startsWith('#')) continue

    if (trimmed.startsWith('[')) {
      const sectionMatch = /^\[([^\]]+)\]/.exec(trimmed)
      if (sectionMatch) {
        currentSection = sectionMatch[1].trim()
      }
      continue
    }

    const eqIndex = trimmed.indexOf('=')
    if (eqIndex === -1) continue

    const key = trimmed.slice(0, eqIndex).trim()
    const value = trimmed.slice(eqIndex + 1).trim()

    if (currentSection === 'defaults') {
      const strVal = unquote(value)
      switch (key) {
        case 'runner':
          config.defaultRunner = strVal
          break
        case 'provider':
          config.defaultProvider = strVal
          break
        case 'model':
          config.defaultModel = strVal
          break
        case 'thinking': {
          const n = parseInt(strVal, 10)
          if (!isNaN(n)) config.defaultThinking = n
          break
        }
      }
    } else if (currentSection === 'abbreviations') {
      config.abbreviations[key] = unquote(value)
    } else if (currentSection.startsWith('aliases.')) {
      const aliasName = currentSection.slice('aliases.'.length)
      if (!config.aliases[aliasName]) {
        config.aliases[aliasName] = {}
      }
      const strVal = unquote(value)
      switch (key) {
        case 'runner':
          config.aliases[aliasName].runner = strVal
          break
        case 'agent':
          config.aliases[aliasName].agent = strVal
          break
        case 'provider':
          config.aliases[aliasName].provider = strVal
          break
        case 'model':
          config.aliases[aliasName].model = strVal
          break
        case 'thinking': {
          const n = parseInt(strVal, 10)
          if (!isNaN(n)) config.aliases[aliasName].thinking = n
          break
        }
      }
    }
  }
}

function unquote(value) {
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1)
  }
  return value
}
