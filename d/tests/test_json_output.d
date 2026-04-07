module test_json_output;

import std.stdio;
import std.string : strip, join;

import call_coding_clis.json_output;

int main() {
    import core.runtime : runModuleUnitTests;
    auto result = runModuleUnitTests();
    return result ? 0 : 1;
}

unittest {
    auto r = parseOpencodeJson("{\"response\": \"hello\"}\n");
    assert(r.events.length == 1);
    assert(r.events[0].eventType == "text");
    assert(r.events[0].text == "hello");
    assert(r.finalText == "hello");
}

unittest {
    auto r = parseOpencodeJson("{\"error\": \"fail\"}\n");
    assert(r.events.length == 1);
    assert(r.events[0].eventType == "error");
    assert(r.errorText == "fail");
}

unittest {
    auto r = parseOpencodeJson("bad\n{\"response\": \"ok\"}\n");
    assert(r.events.length == 1);
    assert(r.finalText == "ok");
}

unittest {
    auto r = parseClaudeCodeJson("{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\"}\n");
    assert(r.sessionId == "s1");
}

unittest {
    auto r = parseClaudeCodeJson("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}\n");
    assert(r.events.length == 1);
    assert(r.events[0].eventType == "assistant");
    assert(r.finalText == "hi");
}

unittest {
    auto r = parseClaudeCodeJson("{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"yo\"}}}\n");
    assert(r.events.length == 1);
    assert(r.events[0].eventType == "text_delta");
    assert(r.events[0].text == "yo");
}

unittest {
    auto r = parseClaudeCodeJson("{\"type\":\"tool_use\",\"tool_name\":\"read\",\"tool_input\":{\"a\":1}}\n");
    assert(r.events.length == 1);
    assert(r.events[0].eventType == "tool_use");
    assert(r.events[0].toolCall !is null);
    assert(r.events[0].toolCall.name == "read");
}

unittest {
    auto r = parseClaudeCodeJson("{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":\"out\",\"is_error\":false}\n");
    assert(r.events.length == 1);
    assert(r.events[0].toolResult !is null);
    assert(r.events[0].toolResult.toolCallId == "t1");
    assert(r.events[0].toolResult.content == "out");
    assert(!r.events[0].toolResult.isError);
}

unittest {
    auto r = parseClaudeCodeJson("{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"done\",\"cost_usd\":0.1,\"duration_ms\":500}\n");
    assert(r.events.length == 1);
    assert(r.finalText == "done");
    assert(r.costUsd == 0.1);
    assert(r.durationMs == 500);
}

unittest {
    auto r = parseClaudeCodeJson("{\"type\":\"result\",\"subtype\":\"error\",\"error\":\"boom\"}\n");
    assert(r.errorText == "boom");
    assert(r.events[0].eventType == "error");
}

unittest {
    auto r = parseKimiJson("{\"role\":\"assistant\",\"content\":\"hello\"}\n");
    assert(r.events.length == 1);
    assert(r.events[0].eventType == "assistant");
    assert(r.finalText == "hello");
}

unittest {
    auto r = parseKimiJson("{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"1\",\"function\":{\"name\":\"bash\",\"arguments\":\"{}\"}}]}\n");
    auto found = false;
    foreach (ev; r.events) {
        if (ev.eventType == "tool_call" && ev.toolCall.name == "bash") found = true;
    }
    assert(found);
}

unittest {
    auto r = parseJsonOutput("{\"response\":\"ok\"}\n", "opencode");
    assert(r.schemaName == "opencode");
    assert(r.finalText == "ok");
}

unittest {
    auto r = parseJsonOutput("", "unknown");
    assert(r.errorText.length > 0);
}

unittest {
    auto r = parseOpencodeJson("{\"response\": \"a\"}\n{\"response\": \"b\"}\n");
    assert(r.finalText == "b");
    assert(r.events.length == 2);
}

unittest {
    ParsedJsonOutput r;
    r.schemaName = "test";
    r.events ~= JsonEvent("text", "hello", "", null, null);
    r.events ~= JsonEvent("assistant", "world", "", null, null);
    auto rendered = renderParsed(r);
    assert(rendered == "hello\nworld");
}

unittest {
    ParsedJsonOutput r;
    r.schemaName = "test";
    r.events ~= JsonEvent("thinking", "", "hmm", null, null);
    auto rendered = renderParsed(r);
    assert(rendered == "[thinking] hmm");
}

unittest {
    ParsedJsonOutput r;
    r.schemaName = "test";
    r.events ~= JsonEvent("tool_use", "", "", new ToolCall("", "read", ""), null);
    r.events ~= JsonEvent("tool_result", "", "", null, new ToolResult("", "output", false));
    auto rendered = renderParsed(r);
    assert(rendered == "[tool] read\n[tool_result] output");
}

unittest {
    ParsedJsonOutput r;
    r.schemaName = "test";
    r.finalText = "fallback";
    auto rendered = renderParsed(r);
    assert(rendered == "fallback");
}

unittest {
    ParsedJsonOutput r;
    r.schemaName = "test";
    r.events ~= JsonEvent("error", "oops", "", null, null);
    auto rendered = renderParsed(r);
    assert(rendered == "[error] oops");
}

unittest {
    auto r = parseKimiJson("{\"type\":\"TurnBegin\"}\n");
    assert(r.events.length == 1);
    assert(r.events[0].eventType == "turnbegin");
}
