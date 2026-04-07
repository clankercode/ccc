#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../src/runner.h"

int main(void) {
    ccc_completed_run result = {0};

    const char *argv[] = {"sh", "-c", "printf 'stdout-ok'; printf 'stderr-ok' >&2; exit 7", NULL};
    if (ccc_run_command(argv, NULL, NULL, &result) != 0) {
        fprintf(stderr, "runner returned failure\n");
        return 1;
    }

    if (result.exit_code != 7) {
        fprintf(stderr, "unexpected exit code: %d\n", result.exit_code);
        ccc_free_completed_run(&result);
        return 1;
    }

    if (strcmp(result.stdout_text, "stdout-ok") != 0) {
        fprintf(stderr, "unexpected stdout: %s\n", result.stdout_text);
        ccc_free_completed_run(&result);
        return 1;
    }

    if (strcmp(result.stderr_text, "stderr-ok") != 0) {
        fprintf(stderr, "unexpected stderr: %s\n", result.stderr_text);
        ccc_free_completed_run(&result);
        return 1;
    }

    ccc_free_completed_run(&result);

    const char *stdin_argv[] = {"sh", "-c", "read value; printf '%s' \"$value\"", NULL};
    if (ccc_run_command(stdin_argv, "stdin-ok\n", NULL, &result) != 0) {
        fprintf(stderr, "runner with stdin returned failure\n");
        return 1;
    }

    if (result.exit_code != 0) {
        fprintf(stderr, "unexpected stdin exit code: %d\n", result.exit_code);
        ccc_free_completed_run(&result);
        return 1;
    }

    if (strcmp(result.stdout_text, "stdin-ok") != 0) {
        fprintf(stderr, "unexpected stdin stdout: %s\n", result.stdout_text);
        ccc_free_completed_run(&result);
        return 1;
    }

    if (strcmp(result.stderr_text, "") != 0) {
        fprintf(stderr, "unexpected stdin stderr: %s\n", result.stderr_text);
        ccc_free_completed_run(&result);
        return 1;
    }

    ccc_free_completed_run(&result);

    const char *cwd_argv[] = {"pwd", NULL};
    if (ccc_run_command(cwd_argv, NULL, "/definitely/not/a/real/directory", &result) != 0) {
        fprintf(stderr, "runner with invalid cwd returned failure\n");
        return 1;
    }

    if (result.exit_code != 127) {
        fprintf(stderr, "unexpected invalid cwd exit code: %d\n", result.exit_code);
        ccc_free_completed_run(&result);
        return 1;
    }

    ccc_free_completed_run(&result);
    return 0;
}
