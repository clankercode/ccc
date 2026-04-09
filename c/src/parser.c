#define _XOPEN_SOURCE 700

#include "parser.h"

#include <ctype.h>
#include <stdio.h>
#include <strings.h>
#include <string.h>

static const RunnerInfo OPENCODE_INFO = {
    .binary = "opencode",
    .extra_args = {"run"},
    .extra_args_count = 1,
    .thinking = {{{0}}, {{0}}, {{0}}, {{0}}, {{0}}},
    .provider_flag = "",
    .model_flag = "",
    .agent_flag = "--agent",
};

static const RunnerInfo CLAUDE_INFO = {
    .binary = "claude",
    .extra_args = {0},
    .extra_args_count = 0,
    .thinking = {
        {.args = {"--no-thinking"}, .count = 1},
        {.args = {"--thinking", "low"}, .count = 2},
        {.args = {"--thinking", "medium"}, .count = 2},
        {.args = {"--thinking", "high"}, .count = 2},
        {.args = {"--thinking", "max"}, .count = 2},
    },
    .provider_flag = "",
    .model_flag = "--model",
    .agent_flag = "--agent",
};

static const RunnerInfo KIMI_INFO = {
    .binary = "kimi",
    .extra_args = {0},
    .extra_args_count = 0,
    .thinking = {
        {.args = {"--no-think"}, .count = 1},
        {.args = {"--think", "low"}, .count = 2},
        {.args = {"--think", "medium"}, .count = 2},
        {.args = {"--think", "high"}, .count = 2},
        {.args = {"--think", "max"}, .count = 2},
    },
    .provider_flag = "",
    .model_flag = "--model",
    .agent_flag = "--agent",
};

static const RunnerInfo CODEX_INFO = {
    .binary = "codex",
    .extra_args = {0},
    .extra_args_count = 0,
    .thinking = {{{0}}, {{0}}, {{0}}, {{0}}, {{0}}},
    .provider_flag = "",
    .model_flag = "--model",
    .agent_flag = "",
};

static const RunnerInfo CRUSH_INFO = {
    .binary = "crush",
    .extra_args = {0},
    .extra_args_count = 0,
    .thinking = {{{0}}, {{0}}, {{0}}, {{0}}, {{0}}},
    .provider_flag = "",
    .model_flag = "",
    .agent_flag = "",
};

void ccc_init_config(CccConfig *config) {
    memset(config, 0, sizeof(*config));
    strncpy(config->default_runner, "oc", sizeof(config->default_runner) - 1);
}

const RunnerInfo *ccc_get_runner(const char *name) {
    if (name == NULL) return NULL;
    if (strcmp(name, "opencode") == 0 || strcmp(name, "oc") == 0) return &OPENCODE_INFO;
    if (strcmp(name, "claude") == 0 || strcmp(name, "cc") == 0 || strcmp(name, "c") == 0) return &CLAUDE_INFO;
    if (strcmp(name, "kimi") == 0 || strcmp(name, "k") == 0) return &KIMI_INFO;
    if (strcmp(name, "codex") == 0 || strcmp(name, "rc") == 0) return &CODEX_INFO;
    if (strcmp(name, "crush") == 0 || strcmp(name, "cr") == 0) return &CRUSH_INFO;
    return NULL;
}

static int is_runner_selector(const char *token) {
    static const char *names[] = {
        "oc", "cc", "c", "k", "rc", "cr",
        "codex", "claude", "opencode", "kimi", "roocode", "crush", "pi", NULL
    };
    for (int i = 0; names[i]; i++) {
        if (strcasecmp(token, names[i]) == 0) return 1;
    }
    return 0;
}

static int parse_thinking_token(const char *token, int *level) {
    if (token[0] != '+') return 0;
    if (token[1] < '0' || token[1] > '4') return 0;
    if (token[2] != '\0') return 0;
    *level = token[1] - '0';
    return 1;
}

static int parse_provider_model_token(const char *token, char *provider, int provider_max, char *model, int model_max) {
    if (token[0] != ':') return 0;
    const char *colon = strchr(token + 1, ':');
    if (colon == NULL) return 0;
    size_t plen = (size_t)(colon - token - 1);
    if (plen == 0 || plen >= (size_t)provider_max) return 0;
    for (size_t i = 0; i < plen; i++) {
        char c = token[1 + i];
        if (!isalnum((unsigned char)c) && c != '_' && c != '-') return 0;
    }
    const char *model_start = colon + 1;
    size_t mlen = strlen(model_start);
    if (mlen == 0 || mlen >= (size_t)model_max) return 0;
    for (size_t i = 0; i < mlen; i++) {
        char c = model_start[i];
        if (!isalnum((unsigned char)c) && c != '_' && c != '-' && c != '.') return 0;
    }
    memcpy(provider, token + 1, plen);
    provider[plen] = '\0';
    memcpy(model, model_start, mlen);
    model[mlen] = '\0';
    return 1;
}

static int parse_model_token(const char *token, char *model, int model_max) {
    if (token[0] != ':') return 0;
    if (token[1] == '\0') return 0;
    if (strchr(token + 1, ':') != NULL) return 0;
    const char *model_start = token + 1;
    size_t mlen = strlen(model_start);
    if (mlen == 0 || mlen >= (size_t)model_max) return 0;
    for (size_t i = 0; i < mlen; i++) {
        char c = model_start[i];
        if (!isalnum((unsigned char)c) && c != '_' && c != '-' && c != '.') return 0;
    }
    memcpy(model, model_start, mlen + 1);
    return 1;
}

static int parse_alias_token(const char *token, char *alias, int alias_max) {
    if (token[0] != '@') return 0;
    if (token[1] == '\0') return 0;
    const char *name = token + 1;
    size_t nlen = strlen(name);
    if (nlen == 0 || nlen >= (size_t)alias_max) return 0;
    for (size_t i = 0; i < nlen; i++) {
        char c = name[i];
        if (!isalnum((unsigned char)c) && c != '_' && c != '-') return 0;
    }
    memcpy(alias, name, nlen + 1);
    return 1;
}

void ccc_parse_args(int argc, char *argv[], ParsedArgs *out) {
    memset(out, 0, sizeof(*out));
    int positional_count = 0;

    for (int i = 1; i < argc; i++) {
        const char *token = argv[i];
        int level;
        char provider[128], model[256], alias[128];

        if (!out->has_runner && positional_count == 0 && is_runner_selector(token)) {
            size_t len = strlen(token);
            if (len >= sizeof(out->runner)) len = sizeof(out->runner) - 1;
            for (size_t j = 0; j < len; j++) {
                out->runner[j] = (char)tolower((unsigned char)token[j]);
            }
            out->runner[len] = '\0';
            out->has_runner = 1;
        } else if (positional_count == 0 && parse_thinking_token(token, &level)) {
            out->thinking = level;
            out->has_thinking = 1;
        } else if (positional_count == 0 && parse_provider_model_token(token, provider, (int)sizeof(provider), model, (int)sizeof(model))) {
            strncpy(out->provider, provider, sizeof(out->provider) - 1);
            strncpy(out->model, model, sizeof(out->model) - 1);
            out->has_provider = 1;
            out->has_model = 1;
        } else if (positional_count == 0 && parse_model_token(token, model, (int)sizeof(model))) {
            strncpy(out->model, model, sizeof(out->model) - 1);
            out->has_model = 1;
        } else if (!out->has_alias && positional_count == 0 && parse_alias_token(token, alias, (int)sizeof(alias))) {
            strncpy(out->alias, alias, sizeof(out->alias) - 1);
            out->has_alias = 1;
        } else {
            if (positional_count > 0) {
                size_t cur = strlen(out->prompt);
                if (cur + 1 < sizeof(out->prompt)) {
                    out->prompt[cur] = ' ';
                }
            }
            size_t cur = strlen(out->prompt);
            size_t tlen = strlen(token);
            if (cur + tlen < sizeof(out->prompt)) {
                memcpy(out->prompt + cur, token, tlen + 1);
            }
            positional_count++;
        }
    }
}

static const char *resolve_runner_name(const char *name, const CccConfig *config) {
    if (name == NULL || name[0] == '\0') {
        return config->default_runner;
    }
    for (int i = 0; i < config->abbrev_count; i++) {
        if (strcmp(config->abbreviations[i].from, name) == 0) {
            return config->abbreviations[i].to;
        }
    }
    return name;
}

static int runner_supports_agent(const RunnerInfo *info) {
    return info != NULL && info->agent_flag != NULL && info->agent_flag[0] != '\0';
}

int ccc_resolve_command(
    ParsedArgs *parsed,
    const CccConfig *config,
    const char *out_argv[],
    int out_argv_max,
    char *out_provider,
    int provider_max,
    char warnings[][CCC_MAX_WARNING_LEN],
    int warnings_max
) {
    const char *runner_name = resolve_runner_name(
        parsed->has_runner ? parsed->runner : NULL, config);

    const RunnerInfo *info = ccc_get_runner(runner_name);
    if (info == NULL) {
        info = ccc_get_runner(config->default_runner);
    }
    if (info == NULL) {
        info = ccc_get_runner("opencode");
    }

    const AliasDef *alias_def = NULL;
    const char *effective_runner_name = runner_name;
    if (parsed->has_alias) {
        for (int i = 0; i < config->alias_count; i++) {
            if (strcmp(config->aliases[i].name, parsed->alias) == 0) {
                alias_def = &config->aliases[i];
                break;
            }
        }
    }

    const RunnerInfo *effective_info = info;
    if (alias_def && alias_def->has_runner && !parsed->has_runner) {
        const char *alias_runner = resolve_runner_name(alias_def->runner, config);
        effective_runner_name = alias_runner;
        const RunnerInfo *alias_info = ccc_get_runner(alias_runner);
        if (alias_info != NULL) effective_info = alias_info;
    }

    int argc = 0;
    out_argv[argc++] = effective_info->binary;
    for (int i = 0; i < effective_info->extra_args_count && argc < out_argv_max - 1; i++) {
        out_argv[argc++] = effective_info->extra_args[i];
    }

    int effective_thinking = -1;
    if (parsed->has_thinking) {
        effective_thinking = parsed->thinking;
    } else if (alias_def && alias_def->has_thinking) {
        effective_thinking = alias_def->thinking;
    }
    if (effective_thinking < 0 && config->has_default_thinking) {
        effective_thinking = config->default_thinking;
    }
    if (effective_thinking >= 0 && effective_thinking <= 4) {
        const ThinkingLevel *tl = &effective_info->thinking[effective_thinking];
        for (int i = 0; i < tl->count && argc < out_argv_max - 1; i++) {
            out_argv[argc++] = tl->args[i];
        }
    }

    const char *effective_provider = NULL;
    if (parsed->has_provider) {
        effective_provider = parsed->provider;
    } else if (alias_def && alias_def->has_provider) {
        effective_provider = alias_def->provider;
    }
    if (effective_provider == NULL && config->default_provider[0] != '\0') {
        effective_provider = config->default_provider;
    }

    const char *effective_model = NULL;
    if (parsed->has_model) {
        effective_model = parsed->model;
    } else if (alias_def && alias_def->has_model) {
        effective_model = alias_def->model;
    }
    if (effective_model == NULL && config->default_model[0] != '\0') {
        effective_model = config->default_model;
    }

    if (effective_model != NULL && effective_model[0] != '\0' && effective_info->model_flag[0] != '\0') {
        if (argc + 2 < out_argv_max) {
            out_argv[argc++] = effective_info->model_flag;
            out_argv[argc++] = effective_model;
        }
    }

    if (out_provider != NULL && provider_max > 0) {
        if (effective_provider != NULL && effective_provider[0] != '\0') {
            strncpy(out_provider, effective_provider, (size_t)(provider_max - 1));
            out_provider[provider_max - 1] = '\0';
        } else {
            out_provider[0] = '\0';
        }
    }

    if (warnings != NULL && warnings_max > 0) {
        warnings[0][0] = '\0';
    }

    const char *effective_agent = NULL;
    if (parsed->has_alias) {
        if (alias_def != NULL && alias_def->has_agent) {
            effective_agent = alias_def->agent;
        } else if (alias_def == NULL) {
            effective_agent = parsed->alias;
        }
    }

    if (effective_agent != NULL && effective_agent[0] != '\0') {
        if (runner_supports_agent(effective_info)) {
            if (argc + 2 < out_argv_max) {
                out_argv[argc++] = effective_info->agent_flag;
                out_argv[argc++] = effective_agent;
            }
        } else if (warnings != NULL && warnings_max > 0) {
            snprintf(
                warnings[0],
                CCC_MAX_WARNING_LEN,
                "warning: runner \"%s\" does not support agents; ignoring @%s",
                effective_runner_name,
                effective_agent
            );
        }
    }

    char *start = parsed->prompt;
    while (*start && isspace((unsigned char)*start)) start++;
    size_t len = strlen(start);
    while (len > 0 && isspace((unsigned char)start[len - 1])) len--;
    if (len == 0) return -1;
    if (start != parsed->prompt) {
        memmove(parsed->prompt, start, len);
    }
    parsed->prompt[len] = '\0';
    if (argc < out_argv_max) {
        out_argv[argc++] = parsed->prompt;
    }

    return argc;
}
