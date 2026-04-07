#include <stdio.h>
#include <string.h>

int ccc_build_prompt_command(const char *prompt, char *buffer, size_t buffer_size);

int main(void) {
    char buffer[256] = {0};
    char tiny_buffer[8] = {0};

    if (ccc_build_prompt_command("Fix the failing tests", buffer, sizeof(buffer)) != 0) {
        fprintf(stderr, "builder returned failure\n");
        return 1;
    }

    if (strcmp(buffer, "opencode run Fix the failing tests") != 0) {
        fprintf(stderr, "unexpected command: %s\n", buffer);
        return 1;
    }

    if (ccc_build_prompt_command("", buffer, sizeof(buffer)) == 0) {
        fprintf(stderr, "empty prompt should fail\n");
        return 1;
    }

    if (ccc_build_prompt_command("Fix the failing tests", tiny_buffer, sizeof(tiny_buffer)) == 0) {
        fprintf(stderr, "tiny buffer should fail\n");
        return 1;
    }

    return 0;
}
