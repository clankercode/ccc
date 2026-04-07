#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    int status = system("./build/ccc 'Fix the failing tests' > ./build/output.txt");
    if (status != 0) {
        fprintf(stderr, "ccc exited unsuccessfully\n");
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

    if (strstr(buffer, "opencode run Fix the failing tests") == NULL) {
        fprintf(stderr, "unexpected output: %s\n", buffer);
        return 1;
    }

    return 0;
}
