#ifndef CCC_PARSER_H
#define CCC_PARSER_H

#include <stddef.h>

#define CCC_MAX_PROMPT 4096
#define CCC_MAX_ARGV 20
#define CCC_MAX_THINKING_ARGS 3

typedef struct {
    const char *args[CCC_MAX_THINKING_ARGS];
    int count;
} ThinkingLevel;

typedef struct {
    const char *binary;
    const char *extra_args[4];
    int extra_args_count;
    ThinkingLevel thinking[5];
    const char *provider_flag;
    const char *model_flag;
} RunnerInfo;

typedef struct {
    char runner[64];
    int thinking;
    char provider[128];
    char model[256];
    char alias[128];
    char prompt[CCC_MAX_PROMPT];
    int has_runner;
    int has_thinking;
    int has_provider;
    int has_model;
    int has_alias;
} ParsedArgs;

typedef struct {
    char name[128];
    char runner[64];
    int thinking;
    char provider[128];
    char model[256];
    int has_runner;
    int has_thinking;
    int has_provider;
    int has_model;
} AliasDef;

#define CCC_MAX_ALIASES 32
#define CCC_MAX_ABBREVS 32

typedef struct {
    char default_runner[64];
    char default_provider[128];
    char default_model[256];
    int default_thinking;
    int has_default_thinking;
    AliasDef aliases[CCC_MAX_ALIASES];
    int alias_count;
    struct {
        char from[64];
        char to[64];
    } abbreviations[CCC_MAX_ABBREVS];
    int abbrev_count;
} CccConfig;

void ccc_init_config(CccConfig *config);
const RunnerInfo *ccc_get_runner(const char *name);
void ccc_parse_args(int argc, char *argv[], ParsedArgs *out);
int ccc_resolve_command(
    ParsedArgs *parsed,
    const CccConfig *config,
    const char *out_argv[],
    int out_argv_max,
    char *out_provider,
    int provider_max
);

#endif
