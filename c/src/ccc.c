#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "config.h"
#include "parser.h"
#include "runner.h"

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: ccc \"<Prompt>\"\n");
        return 1;
    }

    ParsedArgs parsed;
    ccc_parse_args(argc, argv, &parsed);

    CccConfig config;
    ccc_init_config(&config);

    const char *config_path = getenv("CCC_CONFIG");
    if (config_path != NULL) {
        ccc_load_config(config_path, &config);
    }

    const char *cmd_argv[CCC_MAX_ARGV];
    char provider[128] = {0};
    int cmd_argc = ccc_resolve_command(&parsed, &config, cmd_argv, CCC_MAX_ARGV, provider, (int)sizeof(provider));

    if (cmd_argc < 0) {
        fprintf(stderr, "prompt must not be empty\n");
        return 1;
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
