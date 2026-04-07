#include <stdio.h>
#include <string.h>

#include "prompt_spec.h"

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: ccc \"<Prompt>\"\n");
        return 1;
    }

    if (strlen(argv[1]) == 0) {
        fprintf(stderr, "prompt must not be empty\n");
        return 1;
    }

    char buffer[1024] = {0};
    if (ccc_build_prompt_command(argv[1], buffer, sizeof(buffer)) != 0) {
        fprintf(stderr, "prompt must not be empty\n");
        return 1;
    }

    puts(buffer);
    return 0;
}
