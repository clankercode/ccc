#ifndef CCC_JSON_OUTPUT_H
#define CCC_JSON_OUTPUT_H

#define CCC_JO_MAX_EVENTS 256
#define CCC_JO_MAX_TEXT 4096

typedef struct {
    char id[128];
    char name[128];
    char arguments[1024];
} JoToolCall;

typedef struct {
    char tool_call_id[128];
    char content[CCC_JO_MAX_TEXT];
    int is_error;
} JoToolResult;

typedef struct {
    char event_type[64];
    char text[CCC_JO_MAX_TEXT];
    char thinking[CCC_JO_MAX_TEXT];
    int has_tool_call;
    JoToolCall tool_call;
    int has_tool_result;
    JoToolResult tool_result;
} JoEvent;

typedef struct {
    char schema_name[64];
    JoEvent events[CCC_JO_MAX_EVENTS];
    int event_count;
    char final_text[CCC_JO_MAX_TEXT];
    char session_id[256];
    char error[CCC_JO_MAX_TEXT];
    int input_tokens;
    int output_tokens;
    double cost_usd;
    int duration_ms;
} JoParsed;

void jo_init_parsed(JoParsed *out, const char *schema_name);
JoParsed jo_parse_opencode(const char *raw_stdout);
JoParsed jo_parse_claude_code(const char *raw_stdout);
JoParsed jo_parse_kimi(const char *raw_stdout);
JoParsed jo_parse_json_output(const char *raw_stdout, const char *schema);
int jo_render_parsed(const JoParsed *output, char *buf, int buf_max);

#endif
