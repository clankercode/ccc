#define _XOPEN_SOURCE 700

#include "json_output.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static void jo_add_event(JoParsed *out, const JoEvent *ev) {
    if (out->event_count < CCC_JO_MAX_EVENTS) {
        out->events[out->event_count++] = *ev;
    }
}

static void safe_strncpy(char *dst, const char *src, int max) {
    if (!src || !max) return;
    size_t len = strlen(src);
    if ((int)len >= max) len = (size_t)(max - 1);
    memcpy(dst, src, len);
    dst[len] = '\0';
}

static const char *find_key(const char *json, const char *key) {
    char search[256];
    snprintf(search, sizeof(search), "\"%s\"", key);
    size_t slen = strlen(search);
    const char *p = json;
    while ((p = strstr(p, search)) != NULL) {
        const char *after = p + slen;
        while (*after && (*after == ' ' || *after == '\t')) after++;
        if (*after == ':') {
            after++;
            while (*after && (*after == ' ' || *after == '\t')) after++;
            return after;
        }
        p = after;
    }
    return NULL;
}

static int extract_string(const char *json, const char *key, char *out, int out_max) {
    out[0] = '\0';
    const char *p = find_key(json, key);
    if (!p || *p != '"') return 0;
    p++;
    int i = 0;
    while (*p && *p != '"' && i < out_max - 1) {
        if (*p == '\\' && *(p + 1)) {
            p++;
            switch (*p) {
                case '"': out[i++] = '"'; break;
                case '\\': out[i++] = '\\'; break;
                case 'n': out[i++] = '\n'; break;
                case 't': out[i++] = '\t'; break;
                default: out[i++] = *p; break;
            }
        } else {
            out[i++] = *p;
        }
        p++;
    }
    out[i] = '\0';
    return 1;
}

static int extract_bool(const char *json, const char *key) {
    const char *p = find_key(json, key);
    if (!p) return 0;
    return (p[0] == 't' && p[1] == 'r' && p[2] == 'u' && p[3] == 'e');
}

static double extract_double(const char *json, const char *key) {
    const char *p = find_key(json, key);
    if (!p) return 0.0;
    return strtod(p, NULL);
}

static int extract_int(const char *json, const char *key) {
    const char *p = find_key(json, key);
    if (!p) return 0;
    return (int)strtol(p, NULL, 10);
}

static int has_key(const char *json, const char *key) {
    char search[256];
    snprintf(search, sizeof(search), "\"%s\"", key);
    return strstr(json, search) != NULL;
}

static const char *extract_object(const char *json, const char *key, char *out, int out_max) {
    out[0] = '\0';
    const char *p = find_key(json, key);
    if (!p) return NULL;
    if (*p == '{') {
        int depth = 0;
        int i = 0;
        while (*p && i < out_max - 1) {
            if (*p == '{') depth++;
            if (*p == '}') { out[i++] = *p; depth--; if (depth == 0) break; }
            else out[i++] = *p;
            p++;
        }
        out[i] = '\0';
        return out;
    }
    if (*p == '[') {
        int depth = 0;
        int i = 0;
        while (*p && i < out_max - 1) {
            if (*p == '[') depth++;
            if (*p == ']') { out[i++] = *p; depth--; if (depth == 0) break; }
            else out[i++] = *p;
            p++;
        }
        out[i] = '\0';
        return out;
    }
    return NULL;
}

static void to_lower_str(char *s) {
    for (; *s; s++) *s = (char)tolower((unsigned char)*s);
}

void jo_init_parsed(JoParsed *out, const char *schema_name) {
    memset(out, 0, sizeof(*out));
    safe_strncpy(out->schema_name, schema_name, (int)sizeof(out->schema_name));
}

JoParsed jo_parse_opencode(const char *raw_stdout) {
    JoParsed out;
    jo_init_parsed(&out, "opencode");
    if (!raw_stdout) return out;

    char *copy = strdup(raw_stdout);
    char *line = strtok(copy, "\n");
    while (line) {
        while (*line && isspace((unsigned char)*line)) line++;
        if (!*line || *line != '{') { line = strtok(NULL, "\n"); continue; }

        char text[CCC_JO_MAX_TEXT] = {0};
        if (has_key(line, "response")) {
            extract_string(line, "response", text, (int)sizeof(text));
            safe_strncpy(out.final_text, text, (int)sizeof(out.final_text));
            JoEvent ev = {0};
            safe_strncpy(ev.event_type, "text", (int)sizeof(ev.event_type));
            safe_strncpy(ev.text, text, (int)sizeof(ev.text));
            jo_add_event(&out, &ev);
        } else if (has_key(line, "error")) {
            extract_string(line, "error", text, (int)sizeof(text));
            safe_strncpy(out.error, text, (int)sizeof(out.error));
            JoEvent ev = {0};
            safe_strncpy(ev.event_type, "error", (int)sizeof(ev.event_type));
            safe_strncpy(ev.text, text, (int)sizeof(ev.text));
            jo_add_event(&out, &ev);
        }
        line = strtok(NULL, "\n");
    }
    free(copy);
    return out;
}

JoParsed jo_parse_claude_code(const char *raw_stdout) {
    JoParsed out;
    jo_init_parsed(&out, "claude-code");
    if (!raw_stdout) return out;

    char *copy = strdup(raw_stdout);
    char *line = strtok(copy, "\n");
    while (line) {
        while (*line && isspace((unsigned char)*line)) line++;
        if (!*line || *line != '{') { line = strtok(NULL, "\n"); continue; }

        char msg_type[64] = {0};
        extract_string(line, "type", msg_type, (int)sizeof(msg_type));

        if (strcmp(msg_type, "system") == 0) {
            char sub[64] = {0};
            extract_string(line, "subtype", sub, (int)sizeof(sub));
            if (strcmp(sub, "init") == 0) {
                extract_string(line, "session_id", out.session_id, (int)sizeof(out.session_id));
            } else if (strcmp(sub, "api_retry") == 0) {
                JoEvent ev = {0};
                safe_strncpy(ev.event_type, "system_retry", (int)sizeof(ev.event_type));
                jo_add_event(&out, &ev);
            }
        } else if (strcmp(msg_type, "assistant") == 0) {
            char message[8192] = {0};
            extract_object(line, "message", message, (int)sizeof(message));
            char content_arr[8192] = {0};
            extract_object(message, "content", content_arr, (int)sizeof(content_arr));

            if (content_arr[0] == '[') {
                char texts[CCC_JO_MAX_TEXT] = {0};
                int texts_len = 0;
                const char *p = content_arr + 1;
                while (*p) {
                    while (*p && (*p == ' ' || *p == '\t' || *p == ',' || *p == '\n' || *p == '\r')) p++;
                    if (*p == ']' || !*p) break;
                    if (*p == '{') {
                        int depth = 0;
                        const char *start = p;
                        while (*p) {
                            if (*p == '{') depth++;
                            if (*p == '}') { depth--; if (depth == 0) { p++; break; } }
                            p++;
                        }
                        char block[4096] = {0};
                        int blen = (int)(p - start);
                        if (blen >= (int)sizeof(block)) blen = (int)sizeof(block) - 1;
                        memcpy(block, start, blen);
                        block[blen] = '\0';
                        char btype[64] = {0};
                        extract_string(block, "type", btype, (int)sizeof(btype));
                        if (strcmp(btype, "text") == 0) {
                            char btext[4096] = {0};
                            extract_string(block, "text", btext, (int)sizeof(btext));
                            int btlen = (int)strlen(btext);
                            if (texts_len > 0 && texts_len + 1 + btlen < (int)sizeof(texts)) {
                                texts[texts_len++] = '\n';
                            }
                            if (texts_len + btlen < (int)sizeof(texts)) {
                                memcpy(texts + texts_len, btext, btlen);
                                texts_len += btlen;
                            }
                        }
                    } else { p++; }
                }
                if (texts_len > 0) {
                    safe_strncpy(out.final_text, texts, (int)sizeof(out.final_text));
                    JoEvent ev = {0};
                    safe_strncpy(ev.event_type, "assistant", (int)sizeof(ev.event_type));
                    safe_strncpy(ev.text, texts, (int)sizeof(ev.text));
                    jo_add_event(&out, &ev);
                }
            }
        } else if (strcmp(msg_type, "tool_use") == 0) {
            JoEvent ev = {0};
            safe_strncpy(ev.event_type, "tool_use", (int)sizeof(ev.event_type));
            ev.has_tool_call = 1;
            extract_string(line, "tool_name", ev.tool_call.name, (int)sizeof(ev.tool_call.name));
            char tool_input[4096] = {0};
            extract_object(line, "tool_input", tool_input, (int)sizeof(tool_input));
            safe_strncpy(ev.tool_call.arguments, tool_input, (int)sizeof(ev.tool_call.arguments));
            jo_add_event(&out, &ev);
        } else if (strcmp(msg_type, "tool_result") == 0) {
            JoEvent ev = {0};
            safe_strncpy(ev.event_type, "tool_result", (int)sizeof(ev.event_type));
            ev.has_tool_result = 1;
            extract_string(line, "tool_use_id", ev.tool_result.tool_call_id, (int)sizeof(ev.tool_result.tool_call_id));
            extract_string(line, "content", ev.tool_result.content, (int)sizeof(ev.tool_result.content));
            ev.tool_result.is_error = extract_bool(line, "is_error");
            jo_add_event(&out, &ev);
        } else if (strcmp(msg_type, "result") == 0) {
            char sub[64] = {0};
            extract_string(line, "subtype", sub, (int)sizeof(sub));
            if (strcmp(sub, "success") == 0) {
                char res[CCC_JO_MAX_TEXT] = {0};
                extract_string(line, "result", res, (int)sizeof(res));
                if (res[0]) safe_strncpy(out.final_text, res, (int)sizeof(out.final_text));
                out.cost_usd = extract_double(line, "cost_usd");
                out.duration_ms = extract_int(line, "duration_ms");
                JoEvent ev = {0};
                safe_strncpy(ev.event_type, "result", (int)sizeof(ev.event_type));
                safe_strncpy(ev.text, out.final_text, (int)sizeof(ev.text));
                jo_add_event(&out, &ev);
            } else if (strcmp(sub, "error") == 0) {
                extract_string(line, "error", out.error, (int)sizeof(out.error));
                JoEvent ev = {0};
                safe_strncpy(ev.event_type, "error", (int)sizeof(ev.event_type));
                safe_strncpy(ev.text, out.error, (int)sizeof(ev.text));
                jo_add_event(&out, &ev);
            }
        }
        line = strtok(NULL, "\n");
    }
    free(copy);
    return out;
}

JoParsed jo_parse_kimi(const char *raw_stdout) {
    JoParsed out;
    jo_init_parsed(&out, "kimi");
    if (!raw_stdout) return out;

    static const char *passthrough[] = {
        "TurnBegin", "StepBegin", "StepInterrupted", "TurnEnd", "StatusUpdate",
        "HookTriggered", "HookResolved", "ApprovalRequest", "SubagentEvent", "ToolCallRequest", NULL
    };

    char *copy = strdup(raw_stdout);
    char *line = strtok(copy, "\n");
    while (line) {
        while (*line && isspace((unsigned char)*line)) line++;
        if (!*line || *line != '{') { line = strtok(NULL, "\n"); continue; }

        char wire_type[64] = {0};
        extract_string(line, "type", wire_type, (int)sizeof(wire_type));
        if (wire_type[0]) {
            int is_passthrough = 0;
            for (int i = 0; passthrough[i]; i++) {
                if (strcmp(wire_type, passthrough[i]) == 0) { is_passthrough = 1; break; }
            }
            if (is_passthrough) {
                JoEvent ev = {0};
                safe_strncpy(ev.event_type, wire_type, (int)sizeof(ev.event_type));
                to_lower_str(ev.event_type);
                jo_add_event(&out, &ev);
                line = strtok(NULL, "\n");
                continue;
            }
        }

        char role[64] = {0};
        extract_string(line, "role", role, (int)sizeof(role));

        if (strcmp(role, "assistant") == 0) {
            const char *content_p = find_key(line, "content");
            if (content_p && *content_p == '"') {
                char text[CCC_JO_MAX_TEXT] = {0};
                extract_string(line, "content", text, (int)sizeof(text));
                safe_strncpy(out.final_text, text, (int)sizeof(out.final_text));
                JoEvent ev = {0};
                safe_strncpy(ev.event_type, "assistant", (int)sizeof(ev.event_type));
                safe_strncpy(ev.text, text, (int)sizeof(ev.text));
                jo_add_event(&out, &ev);
            } else if (content_p && *content_p == '[') {
                char content_arr[8192] = {0};
                extract_object(line, "content", content_arr, (int)sizeof(content_arr));
                char texts[CCC_JO_MAX_TEXT] = {0};
                int texts_len = 0;
                const char *p = content_arr + 1;
                while (*p) {
                    while (*p && (*p == ' ' || *p == '\t' || *p == ',' || *p == '\n' || *p == '\r')) p++;
                    if (*p == ']' || !*p) break;
                    if (*p == '{') {
                        int depth = 0;
                        const char *start = p;
                        while (*p) {
                            if (*p == '{') depth++;
                            if (*p == '}') { depth--; if (depth == 0) { p++; break; } }
                            p++;
                        }
                        char block[4096] = {0};
                        int blen = (int)(p - start);
                        if (blen >= (int)sizeof(block)) blen = (int)sizeof(block) - 1;
                        memcpy(block, start, blen);
                        block[blen] = '\0';
                        char btype[64] = {0};
                        extract_string(block, "type", btype, (int)sizeof(btype));
                        if (strcmp(btype, "text") == 0) {
                            char btext[4096] = {0};
                            extract_string(block, "text", btext, (int)sizeof(btext));
                            int btlen = (int)strlen(btext);
                            if (texts_len > 0 && texts_len + 1 + btlen < (int)sizeof(texts))
                                texts[texts_len++] = '\n';
                            if (texts_len + btlen < (int)sizeof(texts)) {
                                memcpy(texts + texts_len, btext, btlen);
                                texts_len += btlen;
                            }
                        } else if (strcmp(btype, "think") == 0) {
                            JoEvent ev = {0};
                            safe_strncpy(ev.event_type, "thinking", (int)sizeof(ev.event_type));
                            extract_string(block, "think", ev.thinking, (int)sizeof(ev.thinking));
                            jo_add_event(&out, &ev);
                        }
                    } else { p++; }
                }
                if (texts_len > 0) {
                    safe_strncpy(out.final_text, texts, (int)sizeof(out.final_text));
                    JoEvent ev = {0};
                    safe_strncpy(ev.event_type, "assistant", (int)sizeof(ev.event_type));
                    safe_strncpy(ev.text, texts, (int)sizeof(ev.text));
                    jo_add_event(&out, &ev);
                }
            }

            char tc_arr[8192] = {0};
            if (extract_object(line, "tool_calls", tc_arr, (int)sizeof(tc_arr)) && tc_arr[0] == '[') {
                const char *p = tc_arr + 1;
                while (*p) {
                    while (*p && (*p == ' ' || *p == '\t' || *p == ',' || *p == '\n')) p++;
                    if (*p == ']' || !*p) break;
                    if (*p == '{') {
                        int depth = 0;
                        const char *start = p;
                        while (*p) {
                            if (*p == '{') depth++;
                            if (*p == '}') { depth--; if (depth == 0) { p++; break; } }
                            p++;
                        }
                        char tc_obj[4096] = {0};
                        int tlen = (int)(p - start);
                        if (tlen >= (int)sizeof(tc_obj)) tlen = (int)sizeof(tc_obj) - 1;
                        memcpy(tc_obj, start, tlen);
                        tc_obj[tlen] = '\0';
                        char fn_obj[2048] = {0};
                        extract_object(tc_obj, "function", fn_obj, (int)sizeof(fn_obj));
                        JoEvent ev = {0};
                        safe_strncpy(ev.event_type, "tool_call", (int)sizeof(ev.event_type));
                        ev.has_tool_call = 1;
                        extract_string(tc_obj, "id", ev.tool_call.id, (int)sizeof(ev.tool_call.id));
                        extract_string(fn_obj, "name", ev.tool_call.name, (int)sizeof(ev.tool_call.name));
                        extract_string(fn_obj, "arguments", ev.tool_call.arguments, (int)sizeof(ev.tool_call.arguments));
                        jo_add_event(&out, &ev);
                    } else { p++; }
                }
            }
        } else if (strcmp(role, "tool") == 0) {
            char content_arr[8192] = {0};
            extract_object(line, "content", content_arr, (int)sizeof(content_arr));
            char texts[CCC_JO_MAX_TEXT] = {0};
            int texts_len = 0;
            const char *p = content_arr + 1;
            while (*p) {
                while (*p && (*p == ' ' || *p == '\t' || *p == ',' || *p == '\n' || *p == '\r')) p++;
                if (*p == ']' || !*p) break;
                if (*p == '{') {
                    int depth = 0;
                    const char *start = p;
                    while (*p) {
                        if (*p == '{') depth++;
                        if (*p == '}') { depth--; if (depth == 0) { p++; break; } }
                        p++;
                    }
                    char block[4096] = {0};
                    int blen = (int)(p - start);
                    if (blen >= (int)sizeof(block)) blen = (int)sizeof(block) - 1;
                    memcpy(block, start, blen);
                    block[blen] = '\0';
                    char btype[64] = {0};
                    extract_string(block, "type", btype, (int)sizeof(btype));
                    if (strcmp(btype, "text") == 0) {
                        char btext[4096] = {0};
                        extract_string(block, "text", btext, (int)sizeof(btext));
                        if (strncmp(btext, "<system>", 8) != 0) {
                            int btlen = (int)strlen(btext);
                            if (texts_len > 0 && texts_len + 1 + btlen < (int)sizeof(texts))
                                texts[texts_len++] = '\n';
                            if (texts_len + btlen < (int)sizeof(texts)) {
                                memcpy(texts + texts_len, btext, btlen);
                                texts_len += btlen;
                            }
                        }
                    }
                } else { p++; }
            }
            JoEvent ev = {0};
            safe_strncpy(ev.event_type, "tool_result", (int)sizeof(ev.event_type));
            ev.has_tool_result = 1;
            extract_string(line, "tool_call_id", ev.tool_result.tool_call_id, (int)sizeof(ev.tool_result.tool_call_id));
            safe_strncpy(ev.tool_result.content, texts, (int)sizeof(ev.tool_result.content));
            jo_add_event(&out, &ev);
        }

        line = strtok(NULL, "\n");
    }
    free(copy);
    return out;
}

JoParsed jo_parse_json_output(const char *raw_stdout, const char *schema) {
    if (schema && strcmp(schema, "opencode") == 0) return jo_parse_opencode(raw_stdout);
    if (schema && strcmp(schema, "claude-code") == 0) return jo_parse_claude_code(raw_stdout);
    if (schema && strcmp(schema, "kimi") == 0) return jo_parse_kimi(raw_stdout);
    JoParsed out;
    jo_init_parsed(&out, schema ? schema : "");
    snprintf(out.error, sizeof(out.error), "unknown schema: %s", schema ? schema : "");
    return out;
}

int jo_render_parsed(const JoParsed *output, char *buf, int buf_max) {
    int pos = 0;
    for (int i = 0; i < output->event_count; i++) {
        const JoEvent *ev = &output->events[i];
        const char *et = ev->event_type;
        int need_newline = (pos > 0);

        if (strcmp(et, "text") == 0 || strcmp(et, "assistant") == 0 || strcmp(et, "result") == 0) {
            if (!ev->text[0]) continue;
            int tlen = (int)strlen(ev->text);
            if (need_newline && pos + 1 < buf_max) buf[pos++] = '\n';
            if (pos + tlen < buf_max) { memcpy(buf + pos, ev->text, tlen); pos += tlen; }
        } else if (strcmp(et, "thinking_delta") == 0 || strcmp(et, "thinking") == 0) {
            if (!ev->thinking[0]) continue;
            const char *prefix = "[thinking] ";
            int plen = (int)strlen(prefix);
            int tlen = (int)strlen(ev->thinking);
            if (need_newline && pos + 1 < buf_max) buf[pos++] = '\n';
            if (pos + plen < buf_max) { memcpy(buf + pos, prefix, plen); pos += plen; }
            if (pos + tlen < buf_max) { memcpy(buf + pos, ev->thinking, tlen); pos += tlen; }
        } else if (strcmp(et, "tool_use") == 0) {
            if (!ev->has_tool_call) continue;
            const char *prefix = "[tool] ";
            int plen = (int)strlen(prefix);
            int nlen = (int)strlen(ev->tool_call.name);
            if (need_newline && pos + 1 < buf_max) buf[pos++] = '\n';
            if (pos + plen < buf_max) { memcpy(buf + pos, prefix, plen); pos += plen; }
            if (pos + nlen < buf_max) { memcpy(buf + pos, ev->tool_call.name, nlen); pos += nlen; }
        } else if (strcmp(et, "tool_result") == 0) {
            if (!ev->has_tool_result) continue;
            const char *prefix = "[tool_result] ";
            int plen = (int)strlen(prefix);
            int clen = (int)strlen(ev->tool_result.content);
            if (need_newline && pos + 1 < buf_max) buf[pos++] = '\n';
            if (pos + plen < buf_max) { memcpy(buf + pos, prefix, plen); pos += plen; }
            if (pos + clen < buf_max) { memcpy(buf + pos, ev->tool_result.content, clen); pos += clen; }
        } else if (strcmp(et, "error") == 0) {
            if (!ev->text[0]) continue;
            const char *prefix = "[error] ";
            int plen = (int)strlen(prefix);
            int tlen = (int)strlen(ev->text);
            if (need_newline && pos + 1 < buf_max) buf[pos++] = '\n';
            if (pos + plen < buf_max) { memcpy(buf + pos, prefix, plen); pos += plen; }
            if (pos + tlen < buf_max) { memcpy(buf + pos, ev->text, tlen); pos += tlen; }
        }
    }
    if (pos == 0 && output->final_text[0]) {
        int flen = (int)strlen(output->final_text);
        if (flen >= buf_max) flen = buf_max - 1;
        memcpy(buf, output->final_text, flen);
        pos = flen;
    }
    if (pos < buf_max) buf[pos] = '\0';
    else buf[buf_max - 1] = '\0';
    return pos;
}
