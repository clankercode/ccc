#!/bin/sh
# mock-coding-cli — deterministic mock for cross-language test harness
# Replaces "opencode" during testing. Reacts to known prompts with fixed outputs.
#
# Usage: mock_coding_cli.sh [run] "<prompt>"
# If stdin starts with "PROMPT:", echo the remainder and exit.
# Otherwise, match argv against the prompt table below.
#
# JSON output mode: set MOCK_JSON_SCHEMA to "opencode", "claude-code", "kimi-code", "cursor-agent", or "codex"
# Default (unset): plain text mode (backward compatible)

SCHEMA="${MOCK_JSON_SCHEMA:-}"

# --- JSON output helpers ---

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_opencode() {
    _response="$1"
    printf '{"response":"%s"}\n' "$_response"
}

json_claude_init() {
    printf '{"type":"system","subtype":"init","session_id":"mock-session","tools":[],"model":"mock","permission_mode":"default"}\n'
}

json_claude_assistant() {
    _text="$1"
    printf '{"type":"assistant","message":{"id":"msg_mock","type":"message","role":"assistant","model":"mock","content":[{"type":"text","text":"%s"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}},"session_id":"mock-session"}\n' "$_text"
}

json_claude_result() {
    _text="$1"
    _exit_code="${2:-0}"
    _subtype="success"
    if [ "$_exit_code" -ne 0 ]; then _subtype="error"; fi
    printf '{"type":"result","subtype":"%s","cost_usd":0.0,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"%s","session_id":"mock-session","usage":{"input_tokens":10,"output_tokens":5}}\n' "$_subtype" "$_text"
}

json_claude_tool_use() {
    _tool_name="$1"
    _tool_input="$2"
    printf '{"type":"tool_use","tool_name":"%s","tool_input":%s,"session_id":"mock-session"}\n' "$_tool_name" "$_tool_input"
}

json_claude_tool_result() {
    _tool_use_id="$1"
    _content="$2"
    _is_error="$3"
    printf '{"type":"tool_result","tool_use_id":"%s","content":"%s","is_error":%s,"session_id":"mock-session"}\n' "$_tool_use_id" "$_content" "$_is_error"
}

json_kimi_assistant() {
    _text="$1"
    printf '{"role":"assistant","content":"%s"}\n' "$_text"
}

json_kimi_assistant_with_tool_calls() {
    _text="$1"
    _tool_id="$2"
    _tool_name="$3"
    _tool_args="$4"
    printf '{"role":"assistant","content":"%s","tool_calls":[{"type":"function","id":"%s","function":{"name":"%s","arguments":"%s"}}]}\n' "$_text" "$_tool_id" "$_tool_name" "$_tool_args"
}

json_kimi_tool_result() {
    _tool_call_id="$1"
    _content="$2"
    printf '{"role":"tool","content":[{"type":"text","text":"<system>Tool completed successfully.</system>"},{"type":"text","text":"%s"}],"tool_call_id":"%s"}\n' "$_content" "$_tool_call_id"
}

json_kimi_final() {
    _text="$1"
    printf '{"role":"assistant","content":"%s"}\n' "$_text"
}

json_cursor_init() {
    printf '{"type":"system","subtype":"init","session_id":"mock-cursor","model":"mock","permissionMode":"default"}\n'
}

json_cursor_assistant() {
    _text="$1"
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]},"session_id":"mock-cursor"}\n' "$_text"
}

json_cursor_result() {
    _text="$1"
    _exit_code="${2:-0}"
    _subtype="success"
    if [ "$_exit_code" -ne 0 ]; then _subtype="error"; fi
    printf '{"type":"result","subtype":"%s","duration_ms":100,"duration_api_ms":80,"is_error":false,"result":"%s","session_id":"mock-cursor","usage":{"inputTokens":10,"outputTokens":5}}\n' "$_subtype" "$_text"
}

json_codex_init() {
    printf '{"type":"thread.started","thread_id":"mock-codex"}\n'
    printf '{"type":"turn.started"}\n'
}

json_codex_assistant() {
    _text="$1"
    printf '{"type":"item.completed","item":{"id":"item_mock_message","type":"agent_message","text":"%s"}}\n' "$_text"
}

json_codex_result() {
    printf '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":3,"output_tokens":5}}\n'
}

json_codex_command_start() {
    _command="$1"
    printf '{"type":"item.started","item":{"id":"item_mock_command","type":"command_execution","command":"%s","aggregated_output":"","exit_code":null,"status":"in_progress"}}\n' "$_command"
}

json_codex_command_result() {
    _command="$1"
    _content="$2"
    printf '{"type":"item.completed","item":{"id":"item_mock_command","type":"command_execution","command":"%s","aggregated_output":"%s","exit_code":0,"status":"completed"}}\n' "$_command" "$_content"
}

# --- output dispatcher ---

emit_stdout() {
    _text="$1"
    case "$SCHEMA" in
        opencode)    json_opencode "$_text" ;;
        claude-code) json_claude_init; json_claude_assistant "$_text"; json_claude_result "$_text" 0 ;;
        kimi-code)   json_kimi_assistant "$_text" ;;
        cursor-agent) json_cursor_init; json_cursor_assistant "$_text"; json_cursor_result "$_text" 0 ;;
        codex)       json_codex_init; json_codex_assistant "$_text"; json_codex_result ;;
        *)           printf '%s\n' "$_text" ;;
    esac
}

emit_stderr() {
    _text="$1"
    case "$SCHEMA" in
        opencode)    printf '{"error":"%s"}\n' "$_text" >&2 ;;
        claude-code) printf '{"type":"result","subtype":"error","error":"%s","session_id":"mock-session"}\n' "$_text" >&2 ;;
        kimi-code)   printf '{"role":"tool","content":[{"type":"text","text":"<system>ERROR: %s</system>"}]}\n' "$_text" >&2 ;;
        cursor-agent) printf '{"type":"result","subtype":"error","error":"%s","session_id":"mock-cursor"}\n' "$_text" >&2 ;;
        codex)       printf '{"type":"item.completed","item":{"id":"item_mock_error","type":"agent_message","text":"%s"}}\n' "$_text" >&2 ;;
        *)           printf '%s\n' "$_text" >&2 ;;
    esac
}

emit_exit_42() {
    _text="mock: intentional failure"
    case "$SCHEMA" in
        opencode)
            printf '{"error":"mock: intentional failure"}\n' >&2
            ;;
        claude-code)
            json_claude_init
            json_claude_result "$_text" 42 >&2
            ;;
        kimi-code)
            printf '{"role":"tool","content":[{"type":"text","text":"<system>ERROR: mock: intentional failure</system>"}]}\n' >&2
            ;;
        cursor-agent)
            json_cursor_init
            json_cursor_result "$_text" 42 >&2
            ;;
        codex)
            json_codex_init >&2
            json_codex_assistant "$_text" >&2
            json_codex_result >&2
            ;;
        *)
            printf 'mock: intentional failure\n' >&2
            ;;
    esac
    exit 42
}

emit_mixed_streams() {
    case "$SCHEMA" in
        opencode)
            printf '{"response":"mock: out"}\n'
            printf '{"error":"mock: err"}\n' >&2
            ;;
        claude-code)
            json_claude_init
            json_claude_assistant "mock: out"
            printf '{"type":"result","subtype":"error","error":"mock: err","session_id":"mock-session"}\n' >&2
            ;;
        kimi-code)
            json_kimi_assistant "mock: out"
            printf '{"role":"tool","content":[{"type":"text","text":"<system>ERROR: mock: err</system>"}]}\n' >&2
            ;;
        cursor-agent)
            json_cursor_init
            json_cursor_assistant "mock: out"
            printf '{"type":"result","subtype":"error","error":"mock: err","session_id":"mock-cursor"}\n' >&2
            ;;
        codex)
            json_codex_init
            json_codex_assistant "mock: out"
            json_codex_result
            printf '{"type":"item.completed","item":{"id":"item_mock_error","type":"agent_message","text":"mock: err"}}\n' >&2
            ;;
        *)
            printf 'mock: out\n'
            printf 'mock: err\n' >&2
            ;;
    esac
    exit 1
}

emit_multiline() {
    case "$SCHEMA" in
        opencode)    printf '{"response":"line1\\nline2\\nline3"}\n' ;;
        claude-code)
            json_claude_init
            json_claude_assistant "line1\nline2\nline3"
            json_claude_result "line1\nline2\nline3" 0
            ;;
        kimi-code)   printf '{"role":"assistant","content":"line1\\nline2\\nline3"}\n' ;;
        cursor-agent)
            json_cursor_init
            json_cursor_assistant "line1\nline2\nline3"
            json_cursor_result "line1\nline2\nline3" 0
            ;;
        codex)
            json_codex_init
            json_codex_assistant "line1\nline2\nline3"
            json_codex_result
            ;;
        *)           printf 'line1\nline2\nline3\n' ;;
    esac
    exit 0
}

emit_large_output() {
    _large=$(yes A 2>/dev/null | tr -d '\n' 2>/dev/null | head -c 4096)
    case "$SCHEMA" in
        opencode)    printf '{"response":"%s"}\n' "$_large" ;;
        claude-code)
            json_claude_init
            json_claude_assistant "$_large"
            json_claude_result "$_large" 0
            ;;
        kimi-code)   printf '{"role":"assistant","content":"%s"}\n' "$_large" ;;
        cursor-agent)
            json_cursor_init
            json_cursor_assistant "$_large"
            json_cursor_result "$_large" 0
            ;;
        codex)
            json_codex_init
            json_codex_assistant "$_large"
            json_codex_result
            ;;
        *)           printf '%s\n' "$_large" ;;
    esac
    exit 0
}

emit_stderr_test() {
    case "$SCHEMA" in
        opencode)
            printf '{"response":"mock: stdout output"}\n'
            printf '{"error":"mock: stderr output"}\n' >&2
            ;;
        claude-code)
            json_claude_init
            json_claude_assistant "mock: stdout output"
            json_claude_result "mock: stdout output" 0
            printf '{"type":"system","subtype":"api_retry","attempt":1,"max_retries":1,"retry_delay_ms":0,"error_status":0,"error":"mock: stderr output","session_id":"mock-session"}\n' >&2
            ;;
        kimi-code)
            json_kimi_assistant "mock: stdout output"
            printf '{"role":"tool","content":[{"type":"text","text":"<system>mock: stderr output</system>"}]}\n' >&2
            ;;
        cursor-agent)
            json_cursor_init
            json_cursor_assistant "mock: stdout output"
            json_cursor_result "mock: stdout output" 0
            printf '{"type":"system","subtype":"api_retry","error":"mock: stderr output","session_id":"mock-cursor"}\n' >&2
            ;;
        codex)
            json_codex_init
            json_codex_assistant "mock: stdout output"
            json_codex_result
            printf '{"type":"item.completed","item":{"id":"item_mock_error","type":"agent_message","text":"mock: stderr output"}}\n' >&2
            ;;
        *)
            printf 'mock: stdout output\n'
            printf 'mock: stderr output\n' >&2
            ;;
    esac
    exit 0
}

emit_stdin() {
    _text="$1"
    case "$SCHEMA" in
        opencode)    printf '{"response":"mock: stdin received: %s"}\n' "$_text" ;;
        claude-code)
            json_claude_init
            json_claude_assistant "mock: stdin received: $_text"
            json_claude_result "mock: stdin received: $_text" 0
            ;;
        kimi-code)   printf '{"role":"assistant","content":"mock: stdin received: %s"}\n' "$_text" ;;
        cursor-agent)
            json_cursor_init
            json_cursor_assistant "mock: stdin received: $_text"
            json_cursor_result "mock: stdin received: $_text" 0
            ;;
        codex)
            json_codex_init
            json_codex_assistant "mock: stdin received: $_text"
            json_codex_result
            ;;
        *)           printf 'mock: stdin received: %s\n' "$_text" ;;
    esac
    exit 0
}

emit_unknown() {
    _prompt="$1"
    case "$SCHEMA" in
        opencode)
            _escaped=$(json_escape "mock: unknown prompt '$_prompt'")
            printf '{"response":"%s"}\n' "$_escaped"
            ;;
        claude-code)
            json_claude_init
            json_claude_assistant "mock: unknown prompt '$_prompt'"
            json_claude_result "mock: unknown prompt '$_prompt'" 0
            ;;
        kimi-code)
            _escaped=$(json_escape "mock: unknown prompt '$_prompt'")
            printf '{"role":"assistant","content":"%s"}\n' "$_escaped"
            ;;
        cursor-agent)
            _escaped=$(json_escape "mock: unknown prompt '$_prompt'")
            json_cursor_init
            json_cursor_assistant "$_escaped"
            json_cursor_result "$_escaped" 0
            ;;
        codex)
            _escaped=$(json_escape "mock: unknown prompt '$_prompt'")
            json_codex_init
            json_codex_assistant "$_escaped"
            json_codex_result
            ;;
        *)           printf "mock: unknown prompt '%s'\n" "$_prompt" ;;
    esac
    exit 0
}

emit_usage_error() {
    case "$SCHEMA" in
        opencode)    printf '{"error":"usage: opencode run \\"<Prompt>\\""}\n' >&2 ;;
        claude-code) printf '{"type":"result","subtype":"error","error":"usage: opencode run \\"<Prompt>\\"","session_id":"mock-session"}\n' >&2 ;;
        kimi-code)   printf '{"role":"tool","content":[{"type":"text","text":"<system>ERROR: usage: opencode run \\"<Prompt>\\"</system>"}]}\n' >&2 ;;
        cursor-agent) printf '{"type":"result","subtype":"error","error":"usage: cursor-agent --print \\"<Prompt>\\"","session_id":"mock-cursor"}\n' >&2 ;;
        codex)       printf '{"type":"item.completed","item":{"id":"item_mock_error","type":"agent_message","text":"usage: codex exec \\"<Prompt>\\""}}\n' >&2 ;;
        *)           printf 'usage: opencode run "<Prompt>"\n' >&2 ;;
    esac
    exit 1
}

emit_tool_call() {
    case "$SCHEMA" in
        opencode)
            printf '{"type":"step_start","timestamp":1,"sessionID":"ses_2","part":{"type":"step-start"}}\n'
            printf '{"type":"tool_use","timestamp":2,"sessionID":"ses_2","part":{"type":"tool","tool":"read","callID":"call_1","state":{"status":"completed","input":{"filePath":"/tmp/example.txt","offset":1,"limit":1},"output":"<content>1: hello</content>"}}}\n'
            printf '{"type":"text","timestamp":3,"sessionID":"ses_2","part":{"type":"text","text":"mock: tool call executed"}}\n'
            ;;
        claude-code)
            json_claude_init
            json_claude_tool_use "read_file" '{"path":"/test.py"}'
            json_claude_tool_result "toolu_mock_1" "file contents here" false
            json_claude_assistant "mock: tool call executed"
            json_claude_result "mock: tool call executed" 0
            ;;
        kimi-code)
            json_kimi_assistant_with_tool_calls "Let me read that file." "call_mock_1" "read_file" '{"path":"/test.py"}'
            json_kimi_tool_result "call_mock_1" "file contents here"
            json_kimi_final "mock: tool call executed"
            ;;
        cursor-agent)
            json_cursor_init
            json_cursor_assistant "mock: tool call executed"
            json_cursor_result "mock: tool call executed" 0
            ;;
        codex)
            json_codex_init
            json_codex_command_start "/usr/bin/bash -lc pwd"
            json_codex_command_result "/usr/bin/bash -lc pwd" "/tmp/project\\n"
            json_codex_assistant "mock: tool call executed"
            json_codex_result
            ;;
        *)
            printf 'mock: tool call executed\n'
            ;;
    esac
    exit 0
}

emit_thinking() {
    case "$SCHEMA" in
        opencode)
            printf '{"response":"mock: thinking done"}\n'
            ;;
        claude-code)
            json_claude_init
            printf '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}},"session_id":"mock-session","uuid":"evt-think-1","parent_tool_use_id":null}\n'
            printf '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me think about this..."}},"session_id":"mock-session","uuid":"evt-think-2","parent_tool_use_id":null}\n'
            json_claude_assistant "mock: thinking done"
            json_claude_result "mock: thinking done" 0
            ;;
        kimi-code)
            printf '{"role":"assistant","content":[{"type":"think","think":"Let me think about this...","encrypted":null},{"type":"text","text":"mock: thinking done"}]}\n'
            ;;
        *)
            printf 'mock: thinking done\n'
            ;;
    esac
    exit 0
}

emit_osc_test() {
    case "$SCHEMA" in
        claude-code)
            json_claude_init
            printf '{"type":"assistant","message":{"id":"msg_mock","type":"message","role":"assistant","model":"mock","content":[{"type":"text","text":"pre \\u001b]8;;https://example.com\\u0007link\\u001b]8;;\\u0007 post \\u001b]9;mock title\\u0007\\u0007"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}},"session_id":"mock-session"}\n'
            printf '{"type":"result","subtype":"success","cost_usd":0.0,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"pre \\u001b]8;;https://example.com\\u0007link\\u001b]8;;\\u0007 post \\u001b]9;mock title\\u0007\\u0007","session_id":"mock-session","usage":{"input_tokens":10,"output_tokens":5}}\n'
            ;;
        kimi-code)
            printf '{"role":"assistant","content":"pre \\u001b]8;;https://example.com\\u0007link\\u001b]8;;\\u0007 post \\u001b]9;mock title\\u0007\\u0007"}\n'
            ;;
        opencode)
            printf '{"response":"pre \\u001b]8;;https://example.com\\u0007link\\u001b]8;;\\u0007 post \\u001b]9;mock title\\u0007\\u0007"}\n'
            ;;
        *)
            _hyperlink=$(printf '\033]8;;https://example.com\a')
            _hyperlink_close=$(printf '\033]8;;\a')
            _title=$(printf '\033]9;mock title\a')
            _bell=$(printf '\a')
            _text=$(printf 'pre %slink%s post %s%s' "$_hyperlink" "$_hyperlink_close" "$_title" "$_bell")
            printf '%s\n' "$_text"
            ;;
    esac
    exit 0
}

# --- stdin check (takes priority) ---
stdin_data=""
if [ -t 0 ] 2>/dev/null; then
    : # no stdin
else
    stdin_data=$(cat)
fi

case "$stdin_data" in
    PROMPT:\ *)
        text=$(printf '%s' "$stdin_data" | sed 's/^PROMPT: //')
        emit_stdin "$text"
        ;;
esac

# --- argv parsing ---
if [ "$1" = "run" ] || [ "$1" = "exec" ]; then
    shift
fi

prompt=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p|--print|--trust|--verbose|--include-partial-messages|--no-thinking|--yolo|--plan|--full-auto|--dangerously-skip-permissions|--dangerously-bypass-approvals-and-sandbox|--no-session-persistence|--ephemeral|--save-session|--cleanup-session|--json)
            shift
            ;;
        --thinking)
            if [ "${2:-}" = "enabled" ] || [ "${2:-}" = "disabled" ]; then
                shift 2
            else
                shift
            fi
            ;;
        --output-format|--format|--model|--permission-mode|--agent|--effort|--sandbox|--mode)
            shift 2
            ;;
        --prompt)
            shift
            prompt="$1"
            shift
            ;;
        --)
            shift
            prompt="$*"
            break
            ;;
        *)
            prompt="$*"
            break
            ;;
    esac
done

# --- prompt table ---
case "$prompt" in
    "hello world")
        emit_stdout "mock: ok"
        ;;
    "Fix the failing tests")
        emit_stdout "opencode run Fix the failing tests"
        ;;
    "exit 42")
        emit_exit_42
        ;;
    "stderr test")
        emit_stderr_test
        ;;
    "multiline")
        emit_multiline
        ;;
    "large output")
        emit_large_output
        ;;
    "mixed streams")
        emit_mixed_streams
        ;;
    "special chars \"double\" 'single' & | > < \$backslash")
        emit_stdout "mock: special chars handled"
        ;;
    "tool call")
        emit_tool_call
        ;;
    "thinking")
        emit_thinking
        ;;
    "osc test")
        emit_osc_test
        ;;
    "")
        emit_usage_error
        ;;
    *)
        emit_unknown "$prompt"
        ;;
esac
