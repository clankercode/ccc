#include "prompt_spec.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

int ccc_build_prompt_command(const char *prompt, char *buffer, size_t buffer_size) {
    if (prompt == NULL || buffer == NULL || buffer_size == 0 || strlen(prompt) == 0) {
        return 1;
    }

    size_t index = 0;
    while (prompt[index] != '\0') {
        if (!isspace((unsigned char)prompt[index])) {
            break;
        }
        index += 1;
    }
    if (prompt[index] == '\0') {
        return 1;
    }

    int written = snprintf(buffer, buffer_size, "opencode run %s", &prompt[index]);
    if (written < 0 || (size_t)written >= buffer_size) {
        return 1;
    }

    return 0;
}
