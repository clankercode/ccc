export class TextContent {
  constructor(text) {
    this.text = text
  }
}

export class ThinkingContent {
  constructor(thinking) {
    this.thinking = thinking
  }
}

export class ToolCall {
  constructor(id, name, arguments_) {
    this.id = id
    this.name = name
    this.arguments = arguments_
  }
}

export class ToolResult {
  constructor(tool_call_id, content, is_error = false) {
    this.tool_call_id = tool_call_id
    this.content = content
    this.is_error = is_error
  }
}

export class JsonEvent {
  constructor(event_type, { text = '', thinking = '', tool_call = null, tool_result = null, raw = {} } = {}) {
    this.event_type = event_type
    this.text = text
    this.thinking = thinking
    this.tool_call = tool_call
    this.tool_result = tool_result
    this.raw = raw
  }
}

export class ParsedJsonOutput {
  constructor(schema_name) {
    this.schema_name = schema_name
    this.events = []
    this.final_text = ''
    this.session_id = ''
    this.error = ''
    this.usage = {}
    this.cost_usd = 0.0
    this.duration_ms = 0
    this.raw_lines = []
  }
}

export function parseOpenCodeJson(raw_stdout) {
  const result = new ParsedJsonOutput('opencode')
  for (const line of raw_stdout.trim().split('\n')) {
    const trimmed = line.trim()
    if (!trimmed) continue
    let obj
    try {
      obj = JSON.parse(trimmed)
    } catch {
      continue
    }
    result.raw_lines.push(obj)
    if ('response' in obj) {
      const text = obj.response
      result.final_text = text
      result.events.push(new JsonEvent('text', { text, raw: obj }))
    } else if ('error' in obj) {
      result.error = obj.error
      result.events.push(new JsonEvent('error', { text: obj.error, raw: obj }))
    }
  }
  return result
}

export function parseClaudeCodeJson(raw_stdout) {
  const result = new ParsedJsonOutput('claude-code')
  for (const line of raw_stdout.trim().split('\n')) {
    const trimmed = line.trim()
    if (!trimmed) continue
    let obj
    try {
      obj = JSON.parse(trimmed)
    } catch {
      continue
    }
    result.raw_lines.push(obj)
    const msg_type = obj.type || ''

    if (msg_type === 'system') {
      const sub = obj.subtype || ''
      if (sub === 'init') {
        result.session_id = obj.session_id || ''
      } else if (sub === 'api_retry') {
        result.events.push(new JsonEvent('system_retry', { raw: obj }))
      }

    } else if (msg_type === 'assistant') {
      const message = obj.message || {}
      const content = message.content || []
      const texts = []
      for (const block of content) {
        if (block instanceof Object && block.type === 'text') {
          texts.push(block.text || '')
        }
      }
      if (texts.length) {
        const text = texts.join('\n')
        result.final_text = text
        result.events.push(new JsonEvent('assistant', { text, raw: obj }))
      }
      const usage = message.usage
      if (usage) {
        result.usage = usage
      }

    } else if (msg_type === 'stream_event') {
      const event = obj.event || {}
      const event_type = event.type || ''
      if (event_type === 'content_block_delta') {
        const delta = event.delta || {}
        const delta_type = delta.type || ''
        if (delta_type === 'text_delta') {
          result.events.push(new JsonEvent('text_delta', { text: delta.text || '', raw: obj }))
        } else if (delta_type === 'thinking_delta') {
          result.events.push(new JsonEvent('thinking_delta', { thinking: delta.thinking || '', raw: obj }))
        } else if (delta_type === 'input_json_delta') {
          result.events.push(new JsonEvent('tool_input_delta', { text: delta.partial_json || '', raw: obj }))
        }
      } else if (event_type === 'content_block_start') {
        const cb = event.content_block || {}
        const cb_type = cb.type || ''
        if (cb_type === 'thinking') {
          result.events.push(new JsonEvent('thinking_start', { raw: obj }))
        } else if (cb_type === 'tool_use') {
          result.events.push(new JsonEvent('tool_use_start', {
            tool_call: new ToolCall(cb.id || '', cb.name || '', ''),
            raw: obj,
          }))
        }
      }

    } else if (msg_type === 'tool_use') {
      const tc = new ToolCall('', obj.tool_name || '', JSON.stringify(obj.tool_input || {}))
      result.events.push(new JsonEvent('tool_use', { tool_call: tc, raw: obj }))

    } else if (msg_type === 'tool_result') {
      const tr = new ToolResult(obj.tool_use_id || '', obj.content || '', obj.is_error || false)
      result.events.push(new JsonEvent('tool_result', { tool_result: tr, raw: obj }))

    } else if (msg_type === 'result') {
      const sub = obj.subtype || ''
      if (sub === 'success') {
        result.final_text = obj.result !== undefined ? obj.result : result.final_text
        result.cost_usd = obj.cost_usd !== undefined ? obj.cost_usd : 0.0
        result.duration_ms = obj.duration_ms !== undefined ? obj.duration_ms : 0
        result.usage = obj.usage !== undefined ? obj.usage : result.usage
        result.events.push(new JsonEvent('result', { text: result.final_text, raw: obj }))
      } else if (sub === 'error') {
        result.error = obj.error || ''
        result.events.push(new JsonEvent('error', { text: result.error, raw: obj }))
      }
    }
  }
  return result
}

export function parseKimiJson(raw_stdout) {
  const KIMI_PASSTHROUGH_TYPES = new Set([
    'TurnBegin', 'StepBegin', 'StepInterrupted', 'TurnEnd',
    'StatusUpdate', 'HookTriggered', 'HookResolved',
    'ApprovalRequest', 'SubagentEvent', 'ToolCallRequest',
  ])

  const result = new ParsedJsonOutput('kimi')
  for (const line of raw_stdout.trim().split('\n')) {
    const trimmed = line.trim()
    if (!trimmed) continue
    let obj
    try {
      obj = JSON.parse(trimmed)
    } catch {
      continue
    }
    result.raw_lines.push(obj)

    const wire_type = obj.type || ''
    if (KIMI_PASSTHROUGH_TYPES.has(wire_type)) {
      result.events.push(new JsonEvent(wire_type.toLowerCase(), { raw: obj }))
      continue
    }

    const role = obj.role || ''
    if (role === 'assistant') {
      const content = obj.content
      const tool_calls = obj.tool_calls
      if (typeof content === 'string') {
        result.final_text = content
        result.events.push(new JsonEvent('assistant', { text: content, raw: obj }))
      } else if (Array.isArray(content)) {
        const texts = []
        for (const part of content) {
          if (part instanceof Object) {
            const part_type = part.type || ''
            if (part_type === 'text') {
              texts.push(part.text || '')
            } else if (part_type === 'think') {
              result.events.push(new JsonEvent('thinking', { thinking: part.think || '', raw: obj }))
            }
          }
        }
        if (texts.length) {
          const text = texts.join('\n')
          result.final_text = text
          result.events.push(new JsonEvent('assistant', { text, raw: obj }))
        }
      }
      if (tool_calls) {
        for (const tc_data of tool_calls) {
          const fn = tc_data.function || {}
          const tc = new ToolCall(tc_data.id || '', fn.name || '', fn.arguments || '')
          result.events.push(new JsonEvent('tool_call', { tool_call: tc, raw: obj }))
        }
      }

    } else if (role === 'tool') {
      const content = obj.content || []
      const texts = []
      for (const part of content) {
        if (part instanceof Object && part.type === 'text') {
          const text = part.text || ''
          if (!text.startsWith('<system>')) {
            texts.push(text)
          }
        }
      }
      const tr = new ToolResult(obj.tool_call_id || '', texts.join('\n'))
      result.events.push(new JsonEvent('tool_result', { tool_result: tr, raw: obj }))
    }
  }
  return result
}

const PARSERS = {
  opencode: parseOpenCodeJson,
  'claude-code': parseClaudeCodeJson,
  kimi: parseKimiJson,
}

export function parseJsonOutput(raw_stdout, schema) {
  const parser = PARSERS[schema]
  if (!parser) {
    const result = new ParsedJsonOutput(schema)
    result.error = `unknown schema: ${schema}`
    return result
  }
  return parser(raw_stdout)
}

export function renderParsed(output) {
  const parts = []
  for (const event of output.events) {
    if (event.event_type === 'text' || event.event_type === 'assistant' || event.event_type === 'result') {
      if (event.text) parts.push(event.text)
    } else if (event.event_type === 'thinking_delta' || event.event_type === 'thinking') {
      if (event.thinking) parts.push(`[thinking] ${event.thinking}`)
    } else if (event.event_type === 'tool_use') {
      if (event.tool_call) parts.push(`[tool] ${event.tool_call.name}`)
    } else if (event.event_type === 'tool_result') {
      if (event.tool_result) parts.push(`[tool_result] ${event.tool_result.content}`)
    } else if (event.event_type === 'error') {
      if (event.text) parts.push(`[error] ${event.text}`)
    }
  }
  return parts.length ? parts.join('\n') : output.final_text
}
