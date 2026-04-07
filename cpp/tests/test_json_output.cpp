#include <gtest/gtest.h>
#include <ccc/json_output.hpp>
#include <cmath>
#include <string>

static const std::string OPENCODE_STDOUT = "{\"response\":\"Hello from OpenCode\"}";

static const std::string CLAUDE_CODE_STDOUT =
    "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"sess-1\",\"tools\":[],\"model\":\"mock\",\"permission_mode\":\"default\"}\n"
    "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"mock\","
    "\"content\":[{\"type\":\"text\",\"text\":\"I will help you.\"}],\"stop_reason\":\"end_turn\",\"stop_sequence\":null,"
    "\"usage\":{\"input_tokens\":10,\"output_tokens\":5}},\"session_id\":\"sess-1\"}\n"
    "{\"type\":\"result\",\"subtype\":\"success\",\"cost_usd\":0.003,\"duration_ms\":100,\"duration_api_ms\":80,"
    "\"num_turns\":1,\"result\":\"I will help you.\",\"session_id\":\"sess-1\","
    "\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}\n";

static const std::string CLAUDE_CODE_TOOL_USE =
    "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"sess-2\",\"tools\":[],\"model\":\"mock\",\"permission_mode\":\"default\"}\n"
    "{\"type\":\"tool_use\",\"tool_name\":\"read_file\",\"tool_input\":{\"path\":\"/test.py\"},\"session_id\":\"sess-2\"}\n"
    "{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_1\",\"content\":\"file contents\",\"is_error\":false,\"session_id\":\"sess-2\"}\n"
    "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"Done\",\"session_id\":\"sess-2\",\"cost_usd\":0.0,\"duration_ms\":200,"
    "\"duration_api_ms\":150,\"num_turns\":2,\"usage\":{\"input_tokens\":20,\"output_tokens\":10}}\n";

static const std::string KIMI_STDOUT = "{\"role\":\"assistant\",\"content\":\"Hello from Kimi\"}";

static const std::string KIMI_WITH_TOOL_CALLS =
    "{\"role\":\"assistant\",\"content\":\"Let me read that.\","
    "\"tool_calls\":[{\"type\":\"function\",\"id\":\"call_1\",\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"/src/main.py\\\"}\"}}]}\n"
    "{\"role\":\"tool\",\"content\":[{\"type\":\"text\",\"text\":\"<system>Tool completed successfully.</system>\"},"
    "{\"type\":\"text\",\"text\":\"file contents\"}],\"tool_call_id\":\"call_1\"}\n"
    "{\"role\":\"assistant\",\"content\":\"Done reading the file.\"}";

static const std::string KIMI_THINKING =
    "{\"role\":\"assistant\",\"content\":["
    "{\"type\":\"think\",\"think\":\"I need to analyze this...\",\"encrypted\":null},"
    "{\"type\":\"text\",\"text\":\"Here is my answer\"}]}\n";

TEST(ParseOpenCodeJson, SimpleResponse) {
    auto result = parse_json_output(OPENCODE_STDOUT, "opencode");
    EXPECT_EQ(result.schema_name, "opencode");
    EXPECT_EQ(result.final_text, "Hello from OpenCode");
    EXPECT_EQ(result.events.size(), 1u);
    EXPECT_EQ(result.events[0].event_type, "text");
}

TEST(ParseOpenCodeJson, ErrorResponse) {
    auto result = parse_opencode_json("{\"error\":\"something went wrong\"}");
    EXPECT_EQ(result.error, "something went wrong");
    EXPECT_EQ(result.events.size(), 1u);
    EXPECT_EQ(result.events[0].event_type, "error");
}

TEST(ParseClaudeCodeJson, SimpleResponse) {
    auto result = parse_json_output(CLAUDE_CODE_STDOUT, "claude-code");
    EXPECT_EQ(result.schema_name, "claude-code");
    EXPECT_EQ(result.final_text, "I will help you.");
    EXPECT_EQ(result.session_id, "sess-1");
    EXPECT_NEAR(result.cost_usd, 0.003, 0.0001);
    EXPECT_EQ(result.duration_ms, 100);
}

TEST(ParseClaudeCodeJson, ToolUseAndResult) {
    auto result = parse_claude_code_json(CLAUDE_CODE_TOOL_USE);
    EXPECT_EQ(result.final_text, "Done");
    int tc_count = 0;
    for (auto& e : result.events) if (e.event_type == "tool_use") tc_count++;
    EXPECT_EQ(tc_count, 1);
    for (auto& e : result.events) {
        if (e.event_type == "tool_use") {
            ASSERT_TRUE(e.tool_call.has_value());
            EXPECT_EQ(e.tool_call->name, "read_file");
        }
    }
}

TEST(ParseClaudeCodeJson, ToolResult) {
    auto result = parse_claude_code_json(CLAUDE_CODE_TOOL_USE);
    int tr_count = 0;
    for (auto& e : result.events) if (e.event_type == "tool_result") tr_count++;
    EXPECT_EQ(tr_count, 1);
    for (auto& e : result.events) {
        if (e.event_type == "tool_result") {
            ASSERT_TRUE(e.tool_result.has_value());
            EXPECT_EQ(e.tool_result->tool_call_id, "toolu_1");
            EXPECT_EQ(e.tool_result->content, "file contents");
            EXPECT_FALSE(e.tool_result->is_error);
        }
    }
}

TEST(ParseClaudeCodeJson, ErrorResult) {
    auto result = parse_claude_code_json(
        "{\"type\":\"result\",\"subtype\":\"error\",\"error\":\"rate limited\",\"session_id\":\"s1\"}");
    EXPECT_EQ(result.error, "rate limited");
}

TEST(ParseKimiJson, SimpleResponse) {
    auto result = parse_json_output(KIMI_STDOUT, "kimi");
    EXPECT_EQ(result.schema_name, "kimi");
    EXPECT_EQ(result.final_text, "Hello from Kimi");
}

TEST(ParseKimiJson, ToolCalls) {
    auto result = parse_kimi_json(KIMI_WITH_TOOL_CALLS);
    EXPECT_EQ(result.final_text, "Done reading the file.");
    int tc_count = 0;
    for (auto& e : result.events) if (e.event_type == "tool_call") tc_count++;
    EXPECT_EQ(tc_count, 1);
    for (auto& e : result.events) {
        if (e.event_type == "tool_call") {
            ASSERT_TRUE(e.tool_call.has_value());
            EXPECT_EQ(e.tool_call->name, "read_file");
        }
    }
}

TEST(ParseKimiJson, ToolResult) {
    auto result = parse_kimi_json(KIMI_WITH_TOOL_CALLS);
    int tr_count = 0;
    for (auto& e : result.events) if (e.event_type == "tool_result") tr_count++;
    EXPECT_EQ(tr_count, 1);
    for (auto& e : result.events) {
        if (e.event_type == "tool_result") {
            ASSERT_TRUE(e.tool_result.has_value());
            EXPECT_EQ(e.tool_result->content, "file contents");
        }
    }
}

TEST(ParseKimiJson, Thinking) {
    auto result = parse_kimi_json(KIMI_THINKING);
    int th_count = 0;
    for (auto& e : result.events) if (e.event_type == "thinking") th_count++;
    EXPECT_EQ(th_count, 1);
    for (auto& e : result.events) {
        if (e.event_type == "thinking") {
            EXPECT_EQ(e.thinking, "I need to analyze this...");
        }
    }
    EXPECT_EQ(result.final_text, "Here is my answer");
}

TEST(RenderParsed, OpenCode) {
    auto result = parse_opencode_json(OPENCODE_STDOUT);
    EXPECT_EQ(render_parsed(result), "Hello from OpenCode");
}

TEST(RenderParsed, Claude) {
    auto result = parse_claude_code_json(CLAUDE_CODE_STDOUT);
    auto rendered = render_parsed(result);
    EXPECT_NE(rendered.find("I will help you."), std::string::npos);
}

TEST(RenderParsed, Kimi) {
    auto result = parse_kimi_json(KIMI_STDOUT);
    EXPECT_EQ(render_parsed(result), "Hello from Kimi");
}

TEST(RenderParsed, WithThinking) {
    auto result = parse_kimi_json(KIMI_THINKING);
    auto rendered = render_parsed(result);
    EXPECT_NE(rendered.find("[thinking]"), std::string::npos);
    EXPECT_NE(rendered.find("Here is my answer"), std::string::npos);
}

TEST(RenderParsed, WithToolUse) {
    auto result = parse_claude_code_json(CLAUDE_CODE_TOOL_USE);
    auto rendered = render_parsed(result);
    EXPECT_NE(rendered.find("[tool] read_file"), std::string::npos);
}

TEST(RenderParsed, UnknownSchema) {
    auto result = parse_json_output("{}", "unknown-schema");
    EXPECT_EQ(result.error, "unknown schema: unknown-schema");
}

TEST(RenderParsed, EmptyInput) {
    auto result = parse_opencode_json("");
    EXPECT_EQ(result.final_text, "");
}

TEST(RenderParsed, MalformedJsonSkipped) {
    auto result = parse_opencode_json("not json\n" + OPENCODE_STDOUT);
    EXPECT_EQ(result.final_text, "Hello from OpenCode");
}
