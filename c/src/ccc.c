#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "config.h"
#include "parser.h"
#include "runner.h"

static const char HELP_TEXT[] =
"ccc - call coding CLIs\n"
"\n"
"Usage:\n"
"  ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"\n"
"  ccc --help\n"
"  ccc -h\n"
"\n"
"Slots (in order):\n"
"  runner        Select which coding CLI to use (default: oc)\n"
"                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)\n"
"  +thinking     Set thinking level: +0 (off) through +4 (max)\n"
"  :provider:model  Override provider and model\n"
"  @name         Use a named preset from config; if no preset exists, treat it as an agent\n"
"\n"
"Examples:\n"
"  ccc \"Fix the failing tests\"\n"
"  ccc oc \"Refactor auth module\"\n"
"  ccc cc +2 :anthropic:claude-sonnet-4-20250514 \"Add tests\"\n"
"  ccc k +4 \"Debug the parser\"\n"
"  ccc @reviewer \"Audit the API boundary\"\n"
"  ccc codex \"Write a unit test\"\n"
"\n"
"Config:\n"
"  ~/.config/ccc/config.toml  - default runner, presets, abbreviations\n";

static void print_runner_checklist(FILE *stream) {
    static const char *const runners[][2] = {
        {"opencode", "oc"},
        {"claude", "cc"},
        {"kimi", "k"},
        {"codex", "rc"},
        {"crush", "cr"},
    };

    fprintf(stream, "Runners:\n");
    for (size_t i = 0; i < sizeof(runners) / sizeof(runners[0]); i++) {
        const char *name = runners[i][0];
        const char *binary = runners[i][1];
        const RunnerInfo *info = ccc_get_runner(name);
        if (info != NULL && info->binary != NULL && info->binary[0] != '\0') {
            binary = info->binary;
        }
        if (access(binary, X_OK) == 0) {
            fprintf(stream, "  [+] %-10s (%s)  found\n", name, binary);
        } else {
            fprintf(stream, "  [-] %-10s (%s)  not found\n", name, binary);
        }
    }
}

static void print_help(void) {
    fputs(HELP_TEXT, stdout);
    print_runner_checklist(stdout);
}

static void print_usage(void) {
    fputs("usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"\n", stderr);
    print_runner_checklist(stderr);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage();
        return 1;
    }
    if (argc == 2 && (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
        print_help();
        return 0;
    }

    ParsedArgs parsed;
    ccc_parse_args(argc, argv, &parsed);

    CccConfig config;
    ccc_init_config(&config);

    char config_path[512] = {0};
    if (ccc_find_config_path(
            getenv("CCC_CONFIG"),
            getenv("XDG_CONFIG_HOME"),
            getenv("HOME"),
            config_path,
            sizeof(config_path))) {
        ccc_load_config(config_path, &config);
    }

    const char *cmd_argv[CCC_MAX_ARGV];
    char provider[128] = {0};
    char warnings[1][CCC_MAX_WARNING_LEN] = {{0}};
    int cmd_argc = ccc_resolve_command(
        &parsed,
        &config,
        cmd_argv,
        CCC_MAX_ARGV,
        provider,
        (int)sizeof(provider),
        warnings,
        1
    );

    if (cmd_argc < 0) {
        fprintf(stderr, "prompt must not be empty\n");
        return 1;
    }

    if (warnings[0][0] != '\0') {
        fputs(warnings[0], stderr);
        fputc('\n', stderr);
    }

    const char *real_binary = getenv("CCC_REAL_OPENCODE");
    if (real_binary != NULL) {
        cmd_argv[0] = real_binary;
    }

    char env_str[256] = {0};
    const char *envp[2] = {NULL, NULL};
    if (provider[0] != '\0') {
        snprintf(env_str, sizeof(env_str), "CCC_PROVIDER=%s", provider);
        envp[0] = env_str;
    }

    ccc_completed_run result = {0};
    if (ccc_run_command(cmd_argv, NULL, NULL, envp[0] != NULL ? envp : NULL, &result) != 0) {
        fprintf(stderr, "failed to execute command\n");
        return 1;
    }

    if (result.stdout_text != NULL && result.stdout_text[0] != '\0') {
        printf("%s", result.stdout_text);
    }
    if (result.stderr_text != NULL && result.stderr_text[0] != '\0') {
        fprintf(stderr, "%s", result.stderr_text);
    }

    int exit_code = result.exit_code;
    ccc_free_completed_run(&result);

    return exit_code;
}
