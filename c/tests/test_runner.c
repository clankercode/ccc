#define _XOPEN_SOURCE 700

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../src/runner.h"

int main(void) {
    ccc_completed_run result = {0};

    const char *argv[] = {"sh", "-c", "printf 'stdout-ok'; printf 'stderr-ok' >&2; exit 7", NULL};
    if (ccc_run_command(argv, NULL, NULL, NULL, &result) != 0) {
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
    if (ccc_run_command(stdin_argv, "stdin-ok\n", NULL, NULL, &result) != 0) {
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
    if (ccc_run_command(cwd_argv, NULL, "/definitely/not/a/real/directory", NULL, &result) != 0) {
        fprintf(stderr, "runner with invalid cwd returned failure\n");
        return 1;
    }

    if (result.exit_code != 127) {
        fprintf(stderr, "unexpected invalid cwd exit code: %d\n", result.exit_code);
        ccc_free_completed_run(&result);
        return 1;
    }

    ccc_free_completed_run(&result);

    char cwd_template[] = "/tmp/ccc-runner-cwd-XXXXXX";
    if (mkdtemp(cwd_template) == NULL) {
        fprintf(stderr, "failed to create temp cwd\n");
        return 1;
    }

    const char *envp[] = {"CCC_ENV_TEST=env-ok", NULL};
    const char *shape_argv[] = {
        "sh",
        "-c",
        "printf '%s|%s' "
        "\"$(basename \"$PWD\")\" "
        "\"$CCC_ENV_TEST\"",
        NULL};
    if (ccc_run_command(shape_argv, NULL, cwd_template, envp, &result) != 0) {
        fprintf(stderr, "runner with cwd/env returned failure\n");
        return 1;
    }

    if (result.exit_code != 0) {
        fprintf(stderr, "unexpected cwd/env exit code: %d\n", result.exit_code);
        ccc_free_completed_run(&result);
        return 1;
    }

    if (strstr(result.stdout_text, "env-ok") == NULL) {
        fprintf(stderr, "unexpected cwd/env stdout: %s\n", result.stdout_text);
        ccc_free_completed_run(&result);
        return 1;
    }

    ccc_free_completed_run(&result);

    const char *missing_argv[] = {"/definitely/missing/runner-binary", NULL};
    if (ccc_run_command(missing_argv, NULL, NULL, NULL, &result) != 0) {
        fprintf(stderr, "runner missing-binary returned failure\n");
        return 1;
    }

    if (result.exit_code == 0) {
        fprintf(stderr, "missing binary should not exit successfully\n");
        ccc_free_completed_run(&result);
        return 1;
    }

    if (result.stderr_text == NULL || result.stderr_text[0] == '\0') {
        fprintf(stderr, "missing binary stderr should not be empty\n");
        ccc_free_completed_run(&result);
        return 1;
    }

    ccc_free_completed_run(&result);
    return 0;
}
