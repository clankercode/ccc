use strict;
use warnings;
use Test::More;
use File::Spec;
use lib 'lib';
use Call::Coding::Clis::JsonOutput qw(
    parse_opencode_json parse_claude_code_json parse_kimi_json
    parse_json_output render_parsed
);

my $OPENCODE_STDOUT = '{"response":"Hello from OpenCode"}';

my $CLAUDE_CODE_STDOUT = <<'LINES';
{"type":"system","subtype":"init","session_id":"sess-1","tools":[],"model":"mock","permission_mode":"default"}
{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"mock","content":[{"type":"text","text":"I will help you."}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}},"session_id":"sess-1"}
{"type":"result","subtype":"success","cost_usd":0.003,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"I will help you.","session_id":"sess-1","usage":{"input_tokens":10,"output_tokens":5}}
LINES

my $CLAUDE_CODE_TOOL_USE = <<'LINES';
{"type":"system","subtype":"init","session_id":"sess-2","tools":[],"model":"mock","permission_mode":"default"}
{"type":"tool_use","tool_name":"read_file","tool_input":{"path":"/test.py"},"session_id":"sess-2"}
{"type":"tool_result","tool_use_id":"toolu_1","content":"file contents","is_error":false,"session_id":"sess-2"}
{"type":"result","subtype":"success","result":"Done","session_id":"sess-2","cost_usd":0.0,"duration_ms":200,"duration_api_ms":150,"num_turns":2,"usage":{"input_tokens":20,"output_tokens":10}}
LINES

my $KIMI_STDOUT = '{"role":"assistant","content":"Hello from Kimi"}';

my $KIMI_WITH_TOOL_CALLS = <<'LINES';
{"role":"assistant","content":"Let me read that.","tool_calls":[{"type":"function","id":"call_1","function":{"name":"read_file","arguments":"{\"path\":\"/src/main.py\"}"}}]}
{"role":"tool","content":[{"type":"text","text":"<system>Tool completed successfully.</system>"},{"type":"text","text":"file contents"}],"tool_call_id":"call_1"}
{"role":"assistant","content":"Done reading the file."}
LINES

my $KIMI_THINKING = <<'LINES';
{"role":"assistant","content":[{"type":"think","think":"I need to analyze this...","encrypted":null},{"type":"text","text":"Here is my answer"}]}
LINES

my $CLAUDE_STREAM_UNKNOWN_FIXTURE = do {
    my $path = File::Spec->catfile('tests', 'fixtures', 'runner-transcripts', 'claude', 'stream_unknown_events', 'stdout.ndjson');
    open my $fh, '<', $path or die "open $path: $!";
    local $/;
    <$fh>;
};

# OpenCode tests
{
    my $r = parse_json_output($OPENCODE_STDOUT, 'opencode');
    is $r->{schema_name}, 'opencode', 'opencode: schema_name';
    is $r->{final_text}, 'Hello from OpenCode', 'opencode: final_text';
    is scalar(@{$r->{events}}), 1, 'opencode: 1 event';
    is $r->{events}[0]{event_type}, 'text', 'opencode: event type';
}

{
    my $r = parse_opencode_json('{"error":"something went wrong"}');
    is $r->{error}, 'something went wrong', 'opencode error: error field';
    is scalar(@{$r->{events}}), 1, 'opencode error: 1 event';
    is $r->{events}[0]{event_type}, 'error', 'opencode error: event type';
}

# Claude Code tests
{
    my $r = parse_json_output($CLAUDE_CODE_STDOUT, 'claude-code');
    is $r->{schema_name}, 'claude-code', 'claude: schema_name';
    is $r->{final_text}, 'I will help you.', 'claude: final_text';
    is $r->{session_id}, 'sess-1', 'claude: session_id';
    cmp_ok abs($r->{cost_usd} - 0.003), '<', 0.0001, 'claude: cost_usd';
    is $r->{duration_ms}, 100, 'claude: duration_ms';
}

{
    my $r = parse_claude_code_json($CLAUDE_CODE_TOOL_USE);
    is $r->{final_text}, 'Done', 'claude tool: final_text';
    my @te = grep { $_->{event_type} eq 'tool_use' } @{$r->{events}};
    is scalar(@te), 1, 'claude tool: 1 tool_use event';
    ok $te[0]->{tool_call}, 'claude tool: has tool_call';
    is $te[0]->{tool_call}{name}, 'read_file', 'claude tool: tool name';
}

{
    my $r = parse_claude_code_json($CLAUDE_CODE_TOOL_USE);
    my @tr = grep { $_->{event_type} eq 'tool_result' } @{$r->{events}};
    is scalar(@tr), 1, 'claude tool_result: 1 event';
    ok $tr[0]->{tool_result}, 'claude tool_result: has tool_result';
    is $tr[0]->{tool_result}{tool_call_id}, 'toolu_1', 'claude tool_result: id';
    is $tr[0]->{tool_result}{content}, 'file contents', 'claude tool_result: content';
    ok !$tr[0]->{tool_result}{is_error}, 'claude tool_result: not error';
}

{
    my $r = parse_claude_code_json('{"type":"result","subtype":"error","error":"rate limited","session_id":"s1"}');
    is $r->{error}, 'rate limited', 'claude error: error field';
}

# Kimi tests
{
    my $r = parse_json_output($KIMI_STDOUT, 'kimi');
    is $r->{schema_name}, 'kimi', 'kimi: schema_name';
    is $r->{final_text}, 'Hello from Kimi', 'kimi: final_text';
}

{
    my $r = parse_kimi_json($KIMI_WITH_TOOL_CALLS);
    is $r->{final_text}, 'Done reading the file.', 'kimi tools: final_text';
    my @tc = grep { $_->{event_type} eq 'tool_call' } @{$r->{events}};
    is scalar(@tc), 1, 'kimi tools: 1 tool_call event';
    ok $tc[0]->{tool_call}, 'kimi tools: has tool_call';
    is $tc[0]->{tool_call}{name}, 'read_file', 'kimi tools: tool name';
}

{
    my $r = parse_kimi_json($KIMI_WITH_TOOL_CALLS);
    my @tr = grep { $_->{event_type} eq 'tool_result' } @{$r->{events}};
    is scalar(@tr), 1, 'kimi tool_result: 1 event';
    ok $tr[0]->{tool_result}, 'kimi tool_result: has tool_result';
    is $tr[0]->{tool_result}{content}, 'file contents', 'kimi tool_result: content';
}

{
    my $r = parse_kimi_json($KIMI_THINKING);
    my @th = grep { $_->{event_type} eq 'thinking' } @{$r->{events}};
    is scalar(@th), 1, 'kimi thinking: 1 event';
    is $th[0]->{thinking}, 'I need to analyze this...', 'kimi thinking: content';
    is $r->{final_text}, 'Here is my answer', 'kimi thinking: final_text';
}

# Render tests
{
    my $r = parse_opencode_json($OPENCODE_STDOUT);
    is render_parsed($r), 'Hello from OpenCode', 'render: opencode';
}

{
    my $r = parse_claude_code_json($CLAUDE_CODE_STDOUT);
    like render_parsed($r), qr/I will help you\./, 'render: claude';
}

{
    my $r = parse_kimi_json($KIMI_STDOUT);
    is render_parsed($r), 'Hello from Kimi', 'render: kimi';
}

{
    my $r = parse_kimi_json($KIMI_THINKING);
    my $rendered = render_parsed($r);
    like $rendered, qr/\[thinking\]/, 'render: thinking present';
    like $rendered, qr/Here is my answer/, 'render: thinking text';
}

{
    my $r = parse_claude_code_json($CLAUDE_CODE_TOOL_USE);
    like render_parsed($r), qr/\[tool\] read_file/, 'render: tool use';
}

{
    my $r = parse_json_output('{}', 'unknown-schema');
    is $r->{error}, 'unknown schema: unknown-schema', 'render: unknown schema error';
}

{
    my $r = parse_opencode_json('');
    is $r->{final_text}, '', 'render: empty input';
}

{
    my $r = parse_opencode_json("not json\n$OPENCODE_STDOUT");
    is $r->{final_text}, 'Hello from OpenCode', 'render: malformed skipped';
}

{
    my $r = parse_claude_code_json($CLAUDE_STREAM_UNKNOWN_FIXTURE);
    my $rendered = render_parsed($r);
    like $rendered, qr/Computing the first multiplication\./, 'fixture: rendered known assistant text';
    cmp_ok scalar(@{$r->{raw_lines}}), '>=', 10, 'fixture: keeps many raw lines';
    ok scalar(grep { ($_->{type} // '') eq 'rate_limit_event' } @{$r->{raw_lines}}), 'fixture: keeps rate_limit_event raw line';
    ok scalar(grep { ($_->{type} // '') eq 'stream_event' && (($_->{event} || {})->{type} // '') eq 'message_start' } @{$r->{raw_lines}}), 'fixture: keeps message_start raw line';
    ok scalar(grep { ($_->{type} // '') eq 'stream_event' && (($_->{event} || {})->{type} // '') eq 'message_delta' } @{$r->{raw_lines}}), 'fixture: keeps message_delta raw line';
    ok scalar(grep { ($_->{type} // '') eq 'stream_event' && (($_->{event} || {})->{type} // '') eq 'message_stop' } @{$r->{raw_lines}}), 'fixture: keeps message_stop raw line';
    ok scalar(grep { ($_->{type} // '') eq 'stream_event' && (((($_->{event} || {})->{delta}) || {})->{type} // '') eq 'signature_delta' } @{$r->{raw_lines}}), 'fixture: keeps signature_delta raw line';
}

done_testing;
