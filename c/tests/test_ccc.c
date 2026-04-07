#define _XOPEN_SOURCE 700

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void) {
    // Create a fake opencode script that echoes output
    FILE *fake_opencode = fopen("./build/fake-opencode", "w");
    if (fake_opencode == NULL) {
        fprintf(stderr, "failed to create fake opencode\n");
        return 1;
    }
    fprintf(fake_opencode, "#!/bin/sh\n");
    fprintf(fake_opencode, "echo 'fake-stdout: '$2\n");
    fprintf(fake_opencode, "echo 'fake-stderr: '$2 >&2\n");
    fprintf(fake_opencode, "exit 42\n");
    fclose(fake_opencode);
    chmod("./build/fake-opencode", 0755);

    // Run ccc with the fake opencode via environment variable
    int status = system("CCC_REAL_OPENCODE=./build/fake-opencode ./build/ccc 'Fix the failing tests' > ./build/output.txt 2> ./build/stderr.txt");
    int exit_code = WEXITSTATUS(status);

    // The fake opencode exits with 42, so ccc should too
    if (exit_code != 42) {
        fprintf(stderr, "unexpected exit code: %d (expected 42)\n", exit_code);
        return 1;
    }

    FILE *output = fopen("./build/output.txt", "r");
    if (output == NULL) {
        fprintf(stderr, "failed to open output file\n");
        return 1;
    }

    char buffer[256] = {0};
    fgets(buffer, sizeof(buffer), output);
    fclose(output);

    if (strstr(buffer, "fake-stdout: Fix the failing tests") == NULL) {
        fprintf(stderr, "unexpected stdout: %s\n", buffer);
        return 1;
    }

    FILE *stderr_file = fopen("./build/stderr.txt", "r");
    if (stderr_file == NULL) {
        fprintf(stderr, "failed to open stderr file\n");
        return 1;
    }

    char stderr_buffer[256] = {0};
    fgets(stderr_buffer, sizeof(stderr_buffer), stderr_file);
    fclose(stderr_file);

    if (strstr(stderr_buffer, "fake-stderr: Fix the failing tests") == NULL) {
        fprintf(stderr, "unexpected stderr: %s\n", stderr_buffer);
        return 1;
    }

    // Test missing prompt rejection
    int reject_status = system("./build/ccc '' > /dev/null 2>&1");
    int reject_code = WEXITSTATUS(reject_status);
    if (reject_code != 1) {
        fprintf(stderr, "empty prompt should exit with code 1, got %d\n", reject_code);
        return 1;
    }

    // Test whitespace-only prompt rejection
    int ws_status = system("./build/ccc '   ' > /dev/null 2>&1");
    int ws_code = WEXITSTATUS(ws_status);
    if (ws_code != 1) {
        fprintf(stderr, "whitespace-only prompt should exit with code 1, got %d\n", ws_code);
        return 1;
    }

    // Test prompt trimming: "  hello  " should be sent as "hello"
    int trim_status = system("CCC_REAL_OPENCODE=./build/fake-opencode ./build/ccc '  hello  ' > ./build/trim_output.txt 2> ./build/trim_stderr.txt");
    int trim_exit = WEXITSTATUS(trim_status);
    if (trim_exit != 42) {
        fprintf(stderr, "trimmed prompt test: unexpected exit code %d (expected 42)\n", trim_exit);
        return 1;
    }

    FILE *trim_out = fopen("./build/trim_output.txt", "r");
    if (trim_out == NULL) {
        fprintf(stderr, "failed to open trim output file\n");
        return 1;
    }
    char trim_buffer[256] = {0};
    fgets(trim_buffer, sizeof(trim_buffer), trim_out);
    fclose(trim_out);
    if (strstr(trim_buffer, "fake-stdout: hello") == NULL) {
        fprintf(stderr, "trimmed prompt not sent correctly: %s\n", trim_buffer);
        return 1;
    }

    return 0;
}