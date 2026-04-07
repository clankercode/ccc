#define _XOPEN_SOURCE 700

#include "runner.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static char *ccc_read_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }

    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return NULL;
    }
    rewind(file);

    char *buffer = calloc((size_t)size + 1, 1);
    if (buffer == NULL) {
        fclose(file);
        return NULL;
    }

    if (size > 0 && fread(buffer, 1, (size_t)size, file) != (size_t)size) {
        free(buffer);
        fclose(file);
        return NULL;
    }

    fclose(file);
    return buffer;
}

int ccc_run_command(
    const char *const argv[],
    const char *stdin_text,
    const char *working_directory,
    ccc_completed_run *out_run
) {
    (void)stdin_text;

    char stdout_template[] = "/tmp/ccc-stdout-XXXXXX";
    char stderr_template[] = "/tmp/ccc-stderr-XXXXXX";
    int stdout_fd = mkstemp(stdout_template);
    int stderr_fd = mkstemp(stderr_template);
    if (stdout_fd < 0 || stderr_fd < 0) {
        return 1;
    }

    pid_t child = fork();
    if (child < 0) {
        close(stdout_fd);
        close(stderr_fd);
        return 1;
    }

    if (child == 0) {
        if (working_directory != NULL) {
            chdir(working_directory);
        }
        dup2(stdout_fd, STDOUT_FILENO);
        dup2(stderr_fd, STDERR_FILENO);
        close(stdout_fd);
        close(stderr_fd);
        execvp(argv[0], (char *const *)argv);
        _exit(127);
    }

    close(stdout_fd);
    close(stderr_fd);

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        return 1;
    }

    out_run->stdout_text = ccc_read_file(stdout_template);
    out_run->stderr_text = ccc_read_file(stderr_template);
    out_run->exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 1;

    remove(stdout_template);
    remove(stderr_template);
    return 0;
}

void ccc_free_completed_run(ccc_completed_run *run) {
    if (run == NULL) {
        return;
    }
    free(run->stdout_text);
    free(run->stderr_text);
    run->stdout_text = NULL;
    run->stderr_text = NULL;
    run->exit_code = 0;
}
