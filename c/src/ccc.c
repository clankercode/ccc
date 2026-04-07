#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: ccc \"<Prompt>\"\n");
        return 1;
    }

    if (strlen(argv[1]) == 0) {
        fprintf(stderr, "prompt must not be empty\n");
        return 1;
    }

    printf("opencode run %s\n", argv[1]);
    return 0;
}
