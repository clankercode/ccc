#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "../src/json_output.h"

static int test_count = 0;
static int pass_count = 0;

static void assert_str(const char *actual, const char *expected, const char *label) {
    test_count++;
    if (strcmp(actual, expected) == 0) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: expected \"%s\", got \"%s\"\n", label, expected, actual);
    }
}

static void assert_int(int actual, int expected, const char *label) {
    test_count++;
    if (actual == expected) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: expected %d, got %d\n", label, expected, actual);
    }
}

static void assert_double_near(double actual, double expected, double eps, const char *label) {
    test_count++;
    if (fabs(actual - expected) < eps) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: expected %f, got %f\n", label, expected, actual);
    }
}

static void assert_contains(const char *haystack, const char *needle, const char *label) {
    test_count++;
    if (strstr(haystack, needle) != NULL) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: \"%s\" not found in \"%s\"\n", label, needle, haystack);
    }
}

static const char *OPENCODE_STDOUT = "{\"response\":\"Hello from OpenCode\"}";

static const char *CLAUDE_CODE_STDOUT =
    "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"sess-1\",\"tools\":[],\"model\":\"mock\",\"permission_mode\":\"default\"}\n"
    "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"mock\","
    "\"content\":[{\"type\":\"text\",\"text\":\"I will help you.\"}],\"stop_reason\":\"end_turn\",\"stop_sequence\":null,"
    "\"usage\":{\"input_tokens\":10,\"output_tokens\":5}},\"session_id\":\"sess-1\"}\n"
    "{\"type\":\"result\",\"subtype\":\"success\",\"cost_usd\":0.003,\"duration_ms\":100,\"duration_api_ms\":80,"
    "\"num_turns\":1,\"result\":\"I will help you.\",\"session_id\":\"sess-1\","
    "\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}\n";

static const char *CLAUDE_CODE_TOOL_USE =
    "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"sess-2\",\"tools\":[],\"model\":\"mock\",\"permission_mode\":\"default\"}\n"
    "{\"type\":\"tool_use\",\"tool_name\":\"read_file\",\"tool_input\":{\"path\":\"/test.py\"},\"session_id\":\"sess-2\"}\n"
    "{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_1\",\"content\":\"file contents\",\"is_error\":false,\"session_id\":\"sess-2\"}\n"
    "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"Done\",\"session_id\":\"sess-2\",\"cost_usd\":0.0,\"duration_ms\":200,"
    "\"duration_api_ms\":150,\"num_turns\":2,\"usage\":{\"input_tokens\":20,\"output_tokens\":10}}\n";

static const char *KIMI_STDOUT = "{\"role\":\"assistant\",\"content\":\"Hello from Kimi\"}";

static const char *KIMI_WITH_TOOL_CALLS =
    "{\"role\":\"assistant\",\"content\":\"Let me read that.\","
    "\"tool_calls\":[{\"type\":\"function\",\"id\":\"call_1\",\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"/src/main.py\\\"}\"}}]}\n"
    "{\"role\":\"tool\",\"content\":[{\"type\":\"text\",\"text\":\"<system>Tool completed successfully.</system>\"},"
    "{\"type\":\"text\",\"text\":\"file contents\"}],\"tool_call_id\":\"call_1\"}\n"
    "{\"role\":\"assistant\",\"content\":\"Done reading the file.\"}";

static const char *KIMI_THINKING =
    "{\"role\":\"assistant\",\"content\":["
    "{\"type\":\"think\",\"think\":\"I need to analyze this...\",\"encrypted\":null},"
    "{\"type\":\"text\",\"text\":\"Here is my answer\"}]}\n";

static void test_opencode_simple(void) {
    JoParsed r = jo_parse_json_output(OPENCODE_STDOUT, "opencode");
    assert_str(r.schema_name, "opencode", "oc: schema_name");
    assert_str(r.final_text, "Hello from OpenCode", "oc: final_text");
    assert_int(r.event_count, 1, "oc: event_count");
    assert_str(r.events[0].event_type, "text", "oc: event_type");
}

static void test_opencode_error(void) {
    JoParsed r = jo_parse_opencode("{\"error\":\"something went wrong\"}");
    assert_str(r.error, "something went wrong", "oc-err: error");
    assert_int(r.event_count, 1, "oc-err: event_count");
    assert_str(r.events[0].event_type, "error", "oc-err: event_type");
}

static void test_claude_simple(void) {
    JoParsed r = jo_parse_json_output(CLAUDE_CODE_STDOUT, "claude-code");
    assert_str(r.schema_name, "claude-code", "cc: schema_name");
    assert_str(r.final_text, "I will help you.", "cc: final_text");
    assert_str(r.session_id, "sess-1", "cc: session_id");
    assert_double_near(r.cost_usd, 0.003, 0.0001, "cc: cost_usd");
    assert_int(r.duration_ms, 100, "cc: duration_ms");
}

static void test_claude_tool_use(void) {
    JoParsed r = jo_parse_claude_code(CLAUDE_CODE_TOOL_USE);
    assert_str(r.final_text, "Done", "cc-tool: final_text");
    int tc_count = 0;
    for (int i = 0; i < r.event_count; i++)
        if (strcmp(r.events[i].event_type, "tool_use") == 0) tc_count++;
    assert_int(tc_count, 1, "cc-tool: 1 tool_use");
    for (int i = 0; i < r.event_count; i++) {
        if (strcmp(r.events[i].event_type, "tool_use") == 0) {
            assert_int(r.events[i].has_tool_call, 1, "cc-tool: has_tool_call");
            assert_str(r.events[i].tool_call.name, "read_file", "cc-tool: name");
        }
    }
}

static void test_claude_tool_result(void) {
    JoParsed r = jo_parse_claude_code(CLAUDE_CODE_TOOL_USE);
    int tr_count = 0;
    for (int i = 0; i < r.event_count; i++)
        if (strcmp(r.events[i].event_type, "tool_result") == 0) tr_count++;
    assert_int(tr_count, 1, "cc-tr: 1 tool_result");
    for (int i = 0; i < r.event_count; i++) {
        if (strcmp(r.events[i].event_type, "tool_result") == 0) {
            assert_str(r.events[i].tool_result.tool_call_id, "toolu_1", "cc-tr: id");
            assert_str(r.events[i].tool_result.content, "file contents", "cc-tr: content");
            assert_int(r.events[i].tool_result.is_error, 0, "cc-tr: not error");
        }
    }
}

static void test_claude_error(void) {
    JoParsed r = jo_parse_claude_code("{\"type\":\"result\",\"subtype\":\"error\",\"error\":\"rate limited\",\"session_id\":\"s1\"}");
    assert_str(r.error, "rate limited", "cc-err: error");
}

static void test_kimi_simple(void) {
    JoParsed r = jo_parse_json_output(KIMI_STDOUT, "kimi");
    assert_str(r.schema_name, "kimi", "kimi: schema_name");
    assert_str(r.final_text, "Hello from Kimi", "kimi: final_text");
}

static void test_kimi_tool_calls(void) {
    JoParsed r = jo_parse_kimi(KIMI_WITH_TOOL_CALLS);
    assert_str(r.final_text, "Done reading the file.", "kimi-tc: final_text");
    int tc_count = 0;
    for (int i = 0; i < r.event_count; i++)
        if (strcmp(r.events[i].event_type, "tool_call") == 0) tc_count++;
    assert_int(tc_count, 1, "kimi-tc: 1 tool_call");
    for (int i = 0; i < r.event_count; i++) {
        if (strcmp(r.events[i].event_type, "tool_call") == 0) {
            assert_str(r.events[i].tool_call.name, "read_file", "kimi-tc: name");
        }
    }
}

static void test_kimi_tool_result(void) {
    JoParsed r = jo_parse_kimi(KIMI_WITH_TOOL_CALLS);
    int tr_count = 0;
    for (int i = 0; i < r.event_count; i++)
        if (strcmp(r.events[i].event_type, "tool_result") == 0) tr_count++;
    assert_int(tr_count, 1, "kimi-tr: 1 tool_result");
    for (int i = 0; i < r.event_count; i++) {
        if (strcmp(r.events[i].event_type, "tool_result") == 0) {
            assert_str(r.events[i].tool_result.content, "file contents", "kimi-tr: content");
        }
    }
}

static void test_kimi_thinking(void) {
    JoParsed r = jo_parse_kimi(KIMI_THINKING);
    int th_count = 0;
    for (int i = 0; i < r.event_count; i++)
        if (strcmp(r.events[i].event_type, "thinking") == 0) th_count++;
    assert_int(th_count, 1, "kimi-th: 1 thinking");
    for (int i = 0; i < r.event_count; i++) {
        if (strcmp(r.events[i].event_type, "thinking") == 0) {
            assert_str(r.events[i].thinking, "I need to analyze this...", "kimi-th: thinking");
        }
    }
    assert_str(r.final_text, "Here is my answer", "kimi-th: final_text");
}

static void test_render_opencode(void) {
    JoParsed r = jo_parse_opencode(OPENCODE_STDOUT);
    char buf[8192];
    jo_render_parsed(&r, buf, (int)sizeof(buf));
    assert_str(buf, "Hello from OpenCode", "render: oc");
}

static void test_render_claude(void) {
    JoParsed r = jo_parse_claude_code(CLAUDE_CODE_STDOUT);
    char buf[8192];
    jo_render_parsed(&r, buf, (int)sizeof(buf));
    assert_contains(buf, "I will help you.", "render: cc");
}

static void test_render_kimi(void) {
    JoParsed r = jo_parse_kimi(KIMI_STDOUT);
    char buf[8192];
    jo_render_parsed(&r, buf, (int)sizeof(buf));
    assert_str(buf, "Hello from Kimi", "render: kimi");
}

static void test_render_thinking(void) {
    JoParsed r = jo_parse_kimi(KIMI_THINKING);
    char buf[8192];
    jo_render_parsed(&r, buf, (int)sizeof(buf));
    assert_contains(buf, "[thinking]", "render: thinking tag");
    assert_contains(buf, "Here is my answer", "render: thinking text");
}

static void test_render_tool_use(void) {
    JoParsed r = jo_parse_claude_code(CLAUDE_CODE_TOOL_USE);
    char buf[8192];
    jo_render_parsed(&r, buf, (int)sizeof(buf));
    assert_contains(buf, "[tool] read_file", "render: tool_use");
}

static void test_unknown_schema(void) {
    JoParsed r = jo_parse_json_output("{}", "unknown-schema");
    assert_contains(r.error, "unknown schema", "render: unknown schema");
}

static void test_empty_input(void) {
    JoParsed r = jo_parse_opencode("");
    assert_str(r.final_text, "", "render: empty");
}

static void test_malformed_skipped(void) {
    char input[8192];
    snprintf(input, sizeof(input), "not json\n%s", OPENCODE_STDOUT);
    JoParsed r = jo_parse_opencode(input);
    assert_str(r.final_text, "Hello from OpenCode", "render: malformed skipped");
}

int main(void) {
    test_opencode_simple();
    test_opencode_error();
    test_claude_simple();
    test_claude_tool_use();
    test_claude_tool_result();
    test_claude_error();
    test_kimi_simple();
    test_kimi_tool_calls();
    test_kimi_tool_result();
    test_kimi_thinking();
    test_render_opencode();
    test_render_claude();
    test_render_kimi();
    test_render_thinking();
    test_render_tool_use();
    test_unknown_schema();
    test_empty_input();
    test_malformed_skipped();

    printf("json_output: %d/%d passed\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}
