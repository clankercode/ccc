#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "runner.h"

static int is_whitespace_only(const char *str) {
    while (*str) {
        if (!isspace((unsigned char)*str)) {
            return 0;
        }
        str++;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: ccc \"<Prompt>\"\n");
        return 1;
    }

    const char *prompt = argv[1];
    if (strlen(prompt) == 0 || is_whitespace_only(prompt)) {
        fprintf(stderr, "prompt must not be empty\n");
        return 1;
    }

    // Allow overriding the runner via environment variable for testing
    const char *runner = getenv("CCC_REAL_OPENCODE");
    if (runner == NULL) {
        runner = "opencode";
    }

    const char *cmd_argv[] = {runner, "run", prompt, NULL};

    ccc_completed_run result = {0};
    if (ccc_run_command(cmd_argv, NULL, NULL, NULL, &result) != 0) {
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
