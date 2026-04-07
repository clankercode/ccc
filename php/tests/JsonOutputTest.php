#!/usr/bin/env php
<?php

require_once __DIR__ . '/../src/JsonOutput.php';

use Call\Coding\Clis\JsonOutput;
use Call\Coding\Clis\ParsedJsonOutput;

$passed = 0;
$failed = 0;

function assert_test(string $name, bool $condition): void
{
    global $passed, $failed;
    if ($condition) {
        $passed++;
        echo "ok - $name\n";
    } else {
        $failed++;
        echo "not ok - $name\n";
    }
}

$r = JsonOutput::parseOpencodeJson("{\"response\": \"hello\"}\n");
assert_test('opencode response event', $r->events[0]->eventType === 'text' && $r->events[0]->text === 'hello');
assert_test('opencode final text', $r->finalText === 'hello');

$r = JsonOutput::parseOpencodeJson("{\"error\": \"fail\"}\n");
assert_test('opencode error', $r->error === 'fail' && $r->events[0]->eventType === 'error');

$r = JsonOutput::parseOpencodeJson("bad\n{\"response\": \"ok\"}\n");
assert_test('opencode skips invalid', $r->finalText === 'ok' && count($r->events) === 1);

$r = JsonOutput::parseClaudeCodeJson("{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\"}\n");
assert_test('claude session', $r->sessionId === 's1');

$r = JsonOutput::parseClaudeCodeJson("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}\n");
assert_test('claude assistant', $r->events[0]->eventType === 'assistant' && $r->finalText === 'hi');

$r = JsonOutput::parseClaudeCodeJson("{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"yo\"}}}\n");
assert_test('claude text delta', $r->events[0]->eventType === 'text_delta' && $r->events[0]->text === 'yo');

$r = JsonOutput::parseClaudeCodeJson("{\"type\":\"tool_use\",\"tool_name\":\"read\",\"tool_input\":{\"a\":1}}\n");
assert_test('claude tool use', $r->events[0]->eventType === 'tool_use' && $r->events[0]->toolCall->name === 'read');

$r = JsonOutput::parseClaudeCodeJson("{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":\"out\",\"is_error\":false}\n");
assert_test('claude tool result', $r->events[0]->toolResult->toolCallId === 't1' && $r->events[0]->toolResult->content === 'out');

$r = JsonOutput::parseClaudeCodeJson("{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"done\",\"cost_usd\":0.1,\"duration_ms\":500}\n");
assert_test('claude result success', $r->finalText === 'done' && $r->costUsd === 0.1 && $r->durationMs === 500);

$r = JsonOutput::parseKimiJson("{\"role\":\"assistant\",\"content\":\"hello\"}\n");
assert_test('kimi assistant', $r->events[0]->eventType === 'assistant' && $r->finalText === 'hello');

$r = JsonOutput::parseKimiJson("{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"1\",\"function\":{\"name\":\"bash\",\"arguments\":\"{}\"}}]}\n");
$found = false;
foreach ($r->events as $ev) { if ($ev->eventType === 'tool_call' && $ev->toolCall->name === 'bash') $found = true; }
assert_test('kimi tool call', $found);

$r = JsonOutput::parseJsonOutput("{\"response\":\"ok\"}\n", "opencode");
assert_test('dispatch opencode', $r->schemaName === 'opencode' && $r->finalText === 'ok');

$r = JsonOutput::parseJsonOutput("", "unknown");
assert_test('unknown schema error', strlen($r->error) > 0);

$mock = new ParsedJsonOutput();
$mock->schemaName = 'test';
$mock->events = [
    (function() { $e = new \Call\Coding\Clis\JsonEvent(); $e->eventType = 'text'; $e->text = 'hello'; return $e; })(),
    (function() { $e = new \Call\Coding\Clis\JsonEvent(); $e->eventType = 'assistant'; $e->text = 'world'; return $e; })(),
];
assert_test('render text events', JsonOutput::renderParsed($mock) === "hello\nworld");

$mock2 = new ParsedJsonOutput();
$mock2->schemaName = 'test';
$mock2->finalText = 'fallback';
assert_test('render fallback', JsonOutput::renderParsed($mock2) === 'fallback');

echo "\nResults: $passed passed, $failed failed\n";
exit($failed > 0 ? 1 : 0);
