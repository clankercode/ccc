#include "prompt_spec.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

int ccc_build_prompt_command(const char *prompt, char *buffer, size_t buffer_size) {
    if (prompt == NULL || buffer == NULL || buffer_size == 0 || strlen(prompt) == 0) {
        return 1;
    }

    size_t start = 0;
    while (prompt[start] != '\0') {
        if (!isspace((unsigned char)prompt[start])) {
            break;
        }
        start += 1;
    }

    size_t end = strlen(prompt);
    while (end > start && isspace((unsigned char)prompt[end - 1])) {
        end -= 1;
    }

    if (start == end) {
        return 1;
    }

    size_t trimmed_len = end - start;
    if (trimmed_len + 13 >= buffer_size) {
        return 1;
    }

    memcpy(buffer, "opencode run ", 13);
    memcpy(buffer + 13, prompt + start, trimmed_len);
    buffer[13 + trimmed_len] = '\0';

    return 0;
}
