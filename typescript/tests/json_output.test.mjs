import test from 'node:test'
import assert from 'node:assert/strict'

import {
  JsonEvent, ParsedJsonOutput, ToolCall, ToolResult,
  parseOpenCodeJson, parseClaudeCodeJson, parseKimiJson,
  parseJsonOutput, renderParsed,
} from '../src/json_output.js'

test('parseOpenCodeJson: single response line', () => {
  const input = JSON.stringify({ response: 'hello world' })
  const result = parseOpenCodeJson(input)
  assert.equal(result.schema_name, 'opencode')
  assert.equal(result.final_text, 'hello world')
  assert.equal(result.events.length, 1)
  assert.equal(result.events[0].event_type, 'text')
  assert.equal(result.events[0].text, 'hello world')
})

test('parseOpenCodeJson: error line', () => {
  const input = JSON.stringify({ error: 'something broke' })
  const result = parseOpenCodeJson(input)
  assert.equal(result.error, 'something broke')
  assert.equal(result.events[0].event_type, 'error')
})

test('parseOpenCodeJson: multiple lines with blanks', () => {
  const line1 = JSON.stringify({ response: 'first' })
  const line2 = JSON.stringify({ response: 'second' })
  const input = `${line1}\n\n  \n${line2}`
  const result = parseOpenCodeJson(input)
  assert.equal(result.final_text, 'second')
  assert.equal(result.events.length, 2)
  assert.equal(result.raw_lines.length, 2)
})

test('parseOpenCodeJson: invalid JSON line is skipped', () => {
  const input = `not json\n${JSON.stringify({ response: 'ok' })}`
  const result = parseOpenCodeJson(input)
  assert.equal(result.events.length, 1)
  assert.equal(result.final_text, 'ok')
})

test('parseClaudeCodeJson: system init sets session_id', () => {
  const input = JSON.stringify({ type: 'system', subtype: 'init', session_id: 'sess-123' })
  const result = parseClaudeCodeJson(input)
  assert.equal(result.session_id, 'sess-123')
})

test('parseClaudeCodeJson: assistant message with text blocks', () => {
  const input = JSON.stringify({
    type: 'assistant',
    message: {
      content: [
        { type: 'text', text: 'hello' },
        { type: 'text', text: 'world' },
      ],
      usage: { input_tokens: 10, output_tokens: 5 },
    },
  })
  const result = parseClaudeCodeJson(input)
  assert.equal(result.final_text, 'hello\nworld')
  assert.deepEqual(result.usage, { input_tokens: 10, output_tokens: 5 })
})

test('parseClaudeCodeJson: stream_event thinking_delta and text_delta', () => {
  const thinkLine = JSON.stringify({
    type: 'stream_event',
    event: { type: 'content_block_delta', delta: { type: 'thinking_delta', thinking: 'hmm' } },
  })
  const textLine = JSON.stringify({
    type: 'stream_event',
    event: { type: 'content_block_delta', delta: { type: 'text_delta', text: 'answer' } },
  })
  const result = parseClaudeCodeJson(`${thinkLine}\n${textLine}`)
  assert.equal(result.events.length, 2)
  assert.equal(result.events[0].event_type, 'thinking_delta')
  assert.equal(result.events[0].thinking, 'hmm')
  assert.equal(result.events[1].event_type, 'text_delta')
  assert.equal(result.events[1].text, 'answer')
})

test('parseClaudeCodeJson: tool_use and tool_result', () => {
  const toolUse = JSON.stringify({ type: 'tool_use', tool_name: 'read_file', tool_input: { path: '/foo' } })
  const toolResult = JSON.stringify({ type: 'tool_result', tool_use_id: 'tu-1', content: 'file contents', is_error: false })
  const result = parseClaudeCodeJson(`${toolUse}\n${toolResult}`)
  assert.equal(result.events[0].event_type, 'tool_use')
  assert.equal(result.events[0].tool_call.name, 'read_file')
  assert.equal(result.events[0].tool_call.arguments, JSON.stringify({ path: '/foo' }))
  assert.equal(result.events[1].event_type, 'tool_result')
  assert.equal(result.events[1].tool_result.content, 'file contents')
})

test('parseClaudeCodeJson: result success with cost and duration', () => {
  const input = JSON.stringify({
    type: 'result', subtype: 'success', result: 'done', cost_usd: 0.05, duration_ms: 3200,
  })
  const result = parseClaudeCodeJson(input)
  assert.equal(result.final_text, 'done')
  assert.equal(result.cost_usd, 0.05)
  assert.equal(result.duration_ms, 3200)
})

test('parseClaudeCodeJson: result error', () => {
  const input = JSON.stringify({ type: 'result', subtype: 'error', error: 'timeout' })
  const result = parseClaudeCodeJson(input)
  assert.equal(result.error, 'timeout')
  assert.equal(result.events[0].event_type, 'error')
})

test('parseClaudeCodeJson: content_block_start tool_use', () => {
  const input = JSON.stringify({
    type: 'stream_event',
    event: {
      type: 'content_block_start',
      content_block: { type: 'tool_use', id: 'tc-99', name: 'bash' },
    },
  })
  const result = parseClaudeCodeJson(input)
  assert.equal(result.events[0].event_type, 'tool_use_start')
  assert.equal(result.events[0].tool_call.id, 'tc-99')
  assert.equal(result.events[0].tool_call.name, 'bash')
  assert.equal(result.events[0].tool_call.arguments, '')
})

test('parseKimiJson: assistant with string content', () => {
  const input = JSON.stringify({ role: 'assistant', content: 'hi there' })
  const result = parseKimiJson(input)
  assert.equal(result.final_text, 'hi there')
  assert.equal(result.events[0].event_type, 'assistant')
})

test('parseKimiJson: assistant with list content (text + think)', () => {
  const input = JSON.stringify({
    role: 'assistant',
    content: [
      { type: 'think', think: 'pondering' },
      { type: 'text', text: 'answer' },
    ],
  })
  const result = parseKimiJson(input)
  assert.equal(result.events.length, 2)
  assert.equal(result.events[0].event_type, 'thinking')
  assert.equal(result.events[0].thinking, 'pondering')
  assert.equal(result.events[1].text, 'answer')
  assert.equal(result.final_text, 'answer')
})

test('parseKimiJson: tool_calls and tool result (filters <system>)', () => {
  const assistantLine = JSON.stringify({
    role: 'assistant',
    content: '',
    tool_calls: [{ id: 'call-1', function: { name: 'run', arguments: '{"cmd":"ls"}' } }],
  })
  const toolLine = JSON.stringify({
    role: 'tool',
    tool_call_id: 'call-1',
    content: [
      { type: 'text', text: '<system>internal</system>' },
      { type: 'text', text: 'file.txt' },
    ],
  })
  const result = parseKimiJson(`${assistantLine}\n${toolLine}`)
  const toolCallEvent = result.events.find(e => e.event_type === 'tool_call')
  assert.equal(toolCallEvent.tool_call.name, 'run')
  const toolResultEvent = result.events.find(e => e.event_type === 'tool_result')
  assert.equal(toolResultEvent.tool_result.content, 'file.txt')
  assert.equal(toolResultEvent.tool_result.tool_call_id, 'call-1')
})

test('parseKimiJson: passthrough event types', () => {
  const input = JSON.stringify({ type: 'TurnBegin' }) + '\n' + JSON.stringify({ type: 'StepBegin' })
  const result = parseKimiJson(input)
  assert.equal(result.events.length, 2)
  assert.equal(result.events[0].event_type, 'turnbegin')
  assert.equal(result.events[1].event_type, 'stepbegin')
})

test('parseJsonOutput: dispatches to correct parser', () => {
  const r1 = parseJsonOutput(JSON.stringify({ response: 'oc' }), 'opencode')
  assert.equal(r1.schema_name, 'opencode')
  assert.equal(r1.final_text, 'oc')

  const r2 = parseJsonOutput(JSON.stringify({ type: 'system', subtype: 'init', session_id: 's1' }), 'claude-code')
  assert.equal(r2.session_id, 's1')

  const r3 = parseJsonOutput(JSON.stringify({ role: 'assistant', content: 'k' }), 'kimi')
  assert.equal(r3.final_text, 'k')
})

test('parseJsonOutput: unknown schema returns error', () => {
  const result = parseJsonOutput('', 'unknown')
  assert.equal(result.error, 'unknown schema: unknown')
  assert.equal(result.schema_name, 'unknown')
})

test('renderParsed: text events', () => {
  const output = new ParsedJsonOutput('test')
  output.events.push(new JsonEvent('text', { text: 'hello' }))
  output.events.push(new JsonEvent('assistant', { text: 'world' }))
  output.events.push(new JsonEvent('result', { text: 'done' }))
  assert.equal(renderParsed(output), 'hello\nworld\ndone')
})

test('renderParsed: thinking, tool_use, tool_result, error', () => {
  const output = new ParsedJsonOutput('test')
  output.events.push(new JsonEvent('thinking_delta', { thinking: 'hmm' }))
  output.events.push(new JsonEvent('tool_use', { tool_call: new ToolCall('', 'bash', '{}') }))
  output.events.push(new JsonEvent('tool_result', { tool_result: new ToolResult('', 'output') }))
  output.events.push(new JsonEvent('error', { text: 'fail' }))
  assert.equal(renderParsed(output), '[thinking] hmm\n[tool] bash\n[tool_result] output\n[error] fail')
})

test('renderParsed: falls back to final_text when no renderable events', () => {
  const output = new ParsedJsonOutput('test')
  output.final_text = 'fallback'
  assert.equal(renderParsed(output), 'fallback')
})
