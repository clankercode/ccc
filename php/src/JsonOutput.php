<?php

namespace Call\Coding\Clis;

class ToolCall
{
    public string $id = '';
    public string $name = '';
    public string $arguments = '';
}

class ToolResult
{
    public string $toolCallId = '';
    public string $content = '';
    public bool $isError = false;
}

class JsonEvent
{
    public string $eventType = '';
    public string $text = '';
    public string $thinking = '';
    public ?ToolCall $toolCall = null;
    public ?ToolResult $toolResult = null;
}

class ParsedJsonOutput
{
    public string $schemaName = '';
    public array $events = [];
    public string $finalText = '';
    public string $sessionId = '';
    public string $error = '';
    public float $costUsd = 0.0;
    public int $durationMs = 0;
}

class JsonOutput
{
    private static function getStr(array $obj, string $key): string
    {
        return isset($obj[$key]) && is_string($obj[$key]) ? $obj[$key] : '';
    }

    private static function getBool(array $obj, string $key): bool
    {
        return isset($obj[$key]) && is_bool($obj[$key]) ? $obj[$key] : false;
    }

    private static function getFloat(array $obj, string $key): float
    {
        return isset($obj[$key]) && (is_int($obj[$key]) || is_float($obj[$key])) ? (float)$obj[$key] : 0.0;
    }

    private static function getInt(array $obj, string $key): int
    {
        return isset($obj[$key]) && is_int($obj[$key]) ? $obj[$key] : 0;
    }

    private static function parseLines(string $rawStdout): array
    {
        $lines = [];
        foreach (explode("\n", trim($rawStdout)) as $line) {
            $line = trim($line);
            if ($line === '') continue;
            $obj = json_decode($line, true);
            if (is_array($obj)) $lines[] = $obj;
        }
        return $lines;
    }

    private static function makeEvent(string $type, string $text = '', string $thinking = '', ?ToolCall $tc = null, ?ToolResult $tr = null): JsonEvent
    {
        $ev = new JsonEvent();
        $ev->eventType = $type;
        $ev->text = $text;
        $ev->thinking = $thinking;
        $ev->toolCall = $tc;
        $ev->toolResult = $tr;
        return $ev;
    }

    public static function parseOpencodeJson(string $rawStdout): ParsedJsonOutput
    {
        $result = new ParsedJsonOutput();
        $result->schemaName = 'opencode';

        foreach (self::parseLines($rawStdout) as $obj) {
            if (isset($obj['response']) && is_string($obj['response'])) {
                $text = $obj['response'];
                $result->finalText = $text;
                $result->events[] = self::makeEvent('text', $text);
            } elseif (isset($obj['error']) && is_string($obj['error'])) {
                $result->error = $obj['error'];
                $result->events[] = self::makeEvent('error', $obj['error']);
            }
        }
        return $result;
    }

    public static function parseClaudeCodeJson(string $rawStdout): ParsedJsonOutput
    {
        $result = new ParsedJsonOutput();
        $result->schemaName = 'claude-code';

        foreach (self::parseLines($rawStdout) as $obj) {
            $msgType = self::getStr($obj, 'type');

            if ($msgType === 'system') {
                $sub = self::getStr($obj, 'subtype');
                if ($sub === 'init') {
                    $result->sessionId = self::getStr($obj, 'session_id');
                } elseif ($sub === 'api_retry') {
                    $result->events[] = self::makeEvent('system_retry');
                }
            } elseif ($msgType === 'assistant') {
                $message = $obj['message'] ?? [];
                $content = $message['content'] ?? [];
                $texts = [];
                if (is_array($content)) {
                    foreach ($content as $block) {
                        if (is_array($block) && self::getStr($block, 'type') === 'text') {
                            $texts[] = self::getStr($block, 'text');
                        }
                    }
                }
                if ($texts) {
                    $text = implode("\n", $texts);
                    $result->finalText = $text;
                    $result->events[] = self::makeEvent('assistant', $text);
                }
            } elseif ($msgType === 'stream_event') {
                $event = $obj['event'] ?? [];
                $evType = self::getStr($event, 'type');
                if ($evType === 'content_block_delta') {
                    $delta = $event['delta'] ?? [];
                    $dType = self::getStr($delta, 'type');
                    if ($dType === 'text_delta') {
                        $result->events[] = self::makeEvent('text_delta', self::getStr($delta, 'text'));
                    } elseif ($dType === 'thinking_delta') {
                        $result->events[] = self::makeEvent('thinking_delta', '', self::getStr($delta, 'thinking'));
                    } elseif ($dType === 'input_json_delta') {
                        $result->events[] = self::makeEvent('tool_input_delta', self::getStr($delta, 'partial_json'));
                    }
                } elseif ($evType === 'content_block_start') {
                    $cb = $event['content_block'] ?? [];
                    $cbType = self::getStr($cb, 'type');
                    if ($cbType === 'thinking') {
                        $result->events[] = self::makeEvent('thinking_start');
                    } elseif ($cbType === 'tool_use') {
                        $tc = new ToolCall();
                        $tc->id = self::getStr($cb, 'id');
                        $tc->name = self::getStr($cb, 'name');
                        $result->events[] = self::makeEvent('tool_use_start', '', '', $tc);
                    }
                }
            } elseif ($msgType === 'tool_use') {
                $tc = new ToolCall();
                $tc->name = self::getStr($obj, 'tool_name');
                $tc->arguments = json_encode($obj['tool_input'] ?? new \stdClass());
                $result->events[] = self::makeEvent('tool_use', '', '', $tc);
            } elseif ($msgType === 'tool_result') {
                $tr = new ToolResult();
                $tr->toolCallId = self::getStr($obj, 'tool_use_id');
                $tr->content = self::getStr($obj, 'content');
                $tr->isError = self::getBool($obj, 'is_error');
                $result->events[] = self::makeEvent('tool_result', '', '', null, $tr);
            } elseif ($msgType === 'result') {
                $sub = self::getStr($obj, 'subtype');
                if ($sub === 'success') {
                    $res = self::getStr($obj, 'result');
                    if ($res !== '') $result->finalText = $res;
                    $result->costUsd = self::getFloat($obj, 'cost_usd');
                    $result->durationMs = self::getInt($obj, 'duration_ms');
                    $result->events[] = self::makeEvent('result', $result->finalText);
                } elseif ($sub === 'error') {
                    $result->error = self::getStr($obj, 'error');
                    $result->events[] = self::makeEvent('error', $result->error);
                }
            }
        }
        return $result;
    }

    private static array $kimiPassthrough = [
        'TurnBegin', 'StepBegin', 'StepInterrupted', 'TurnEnd',
        'StatusUpdate', 'HookTriggered', 'HookResolved', 'ApprovalRequest',
        'SubagentEvent', 'ToolCallRequest',
    ];

    public static function parseKimiJson(string $rawStdout): ParsedJsonOutput
    {
        $result = new ParsedJsonOutput();
        $result->schemaName = 'kimi';

        foreach (self::parseLines($rawStdout) as $obj) {
            $wireType = self::getStr($obj, 'type');
            if ($wireType !== '' && in_array($wireType, self::$kimiPassthrough)) {
                $result->events[] = self::makeEvent(strtolower($wireType));
                continue;
            }

            $role = self::getStr($obj, 'role');
            if ($role === 'assistant') {
                $contentVal = $obj['content'] ?? null;
                if (is_string($contentVal)) {
                    $result->finalText = $contentVal;
                    $result->events[] = self::makeEvent('assistant', $contentVal);
                } elseif (is_array($contentVal)) {
                    $texts = [];
                    foreach ($contentVal as $part) {
                        if (!is_array($part)) continue;
                        $pt = self::getStr($part, 'type');
                        if ($pt === 'text') $texts[] = self::getStr($part, 'text');
                        elseif ($pt === 'think') $result->events[] = self::makeEvent('thinking', '', self::getStr($part, 'think'));
                    }
                    if ($texts) {
                        $text = implode("\n", $texts);
                        $result->finalText = $text;
                        $result->events[] = self::makeEvent('assistant', $text);
                    }
                }

                $toolCalls = $obj['tool_calls'] ?? [];
                if (is_array($toolCalls)) {
                    foreach ($toolCalls as $tcData) {
                        if (!is_array($tcData)) continue;
                        $tc = new ToolCall();
                        $tc->id = self::getStr($tcData, 'id');
                        $fn = $tcData['function'] ?? [];
                        $tc->name = self::getStr($fn, 'name');
                        $tc->arguments = self::getStr($fn, 'arguments');
                        $result->events[] = self::makeEvent('tool_call', '', '', $tc);
                    }
                }
            } elseif ($role === 'tool') {
                $content = $obj['content'] ?? [];
                $texts = [];
                if (is_array($content)) {
                    foreach ($content as $part) {
                        if (!is_array($part)) continue;
                        if (self::getStr($part, 'type') === 'text') {
                            $t = self::getStr($part, 'text');
                            if (!str_starts_with($t, '<system>')) $texts[] = $t;
                        }
                    }
                }
                $tr = new ToolResult();
                $tr->toolCallId = self::getStr($obj, 'tool_call_id');
                $tr->content = implode("\n", $texts);
                $result->events[] = self::makeEvent('tool_result', '', '', null, $tr);
            }
        }
        return $result;
    }

    public static function parseJsonOutput(string $rawStdout, string $schema): ParsedJsonOutput
    {
        return match ($schema) {
            'opencode' => self::parseOpencodeJson($rawStdout),
            'claude-code' => self::parseClaudeCodeJson($rawStdout),
            'kimi' => self::parseKimiJson($rawStdout),
            default => (function () use ($schema) {
                $r = new ParsedJsonOutput();
                $r->schemaName = $schema;
                $r->error = "unknown schema: $schema";
                return $r;
            })(),
        };
    }

    public static function renderParsed(ParsedJsonOutput $output): string
    {
        $parts = [];
        foreach ($output->events as $ev) {
            switch ($ev->eventType) {
                case 'text': case 'assistant': case 'result':
                    if ($ev->text !== '') $parts[] = $ev->text;
                    break;
                case 'thinking_delta': case 'thinking':
                    if ($ev->thinking !== '') $parts[] = "[thinking] {$ev->thinking}";
                    break;
                case 'tool_use':
                    if ($ev->toolCall) $parts[] = "[tool] {$ev->toolCall->name}";
                    break;
                case 'tool_result':
                    if ($ev->toolResult) $parts[] = "[tool_result] {$ev->toolResult->content}";
                    break;
                case 'error':
                    if ($ev->text !== '') $parts[] = "[error] {$ev->text}";
                    break;
            }
        }
        return $parts ? implode("\n", $parts) : $output->finalText;
    }
}
