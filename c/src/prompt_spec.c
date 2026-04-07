#include "prompt_spec.h"

#include <stdio.h>
#include <string.h>

int ccc_build_prompt_command(const char *prompt, char *buffer, size_t buffer_size) {
    if (prompt == NULL || buffer == NULL || buffer_size == 0 || strlen(prompt) == 0) {
        return 1;
    }

    int written = snprintf(buffer, buffer_size, "opencode run %s", prompt);
    if (written < 0 || (size_t)written >= buffer_size) {
        return 1;
    }

    return 0;
}
