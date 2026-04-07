#define _XOPEN_SOURCE 700

#include "runner.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
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

static int ccc_write_all(int fd, const char *text) {
    size_t remaining = strlen(text);
    const char *cursor = text;

    while (remaining > 0) {
        ssize_t written = write(fd, cursor, remaining);
        if (written <= 0) {
            return 1;
        }
        cursor += (size_t)written;
        remaining -= (size_t)written;
    }

    return 0;
}

int ccc_run_command(
    const char *const argv[],
    const char *stdin_text,
    const char *working_directory,
    const char *const envp[],
    ccc_completed_run *out_run
) {
    if (argv == NULL || argv[0] == NULL || out_run == NULL) {
        return 1;
    }

    char stdout_template[] = "/tmp/ccc-stdout-XXXXXX";
    char stderr_template[] = "/tmp/ccc-stderr-XXXXXX";
    int stdout_fd = mkstemp(stdout_template);
    int stderr_fd = mkstemp(stderr_template);
    int stdin_fd = -1;
    int stdin_pipe[2] = {-1, -1};
    if (stdout_fd < 0 || stderr_fd < 0) {
        if (stdout_fd >= 0) {
            close(stdout_fd);
            remove(stdout_template);
        }
        if (stderr_fd >= 0) {
            close(stderr_fd);
            remove(stderr_template);
        }
        return 1;
    }

    if (stdin_text == NULL) {
        stdin_fd = open("/dev/null", O_RDONLY);
        if (stdin_fd < 0) {
            close(stdout_fd);
            close(stderr_fd);
            remove(stdout_template);
            remove(stderr_template);
            return 1;
        }
    } else if (pipe(stdin_pipe) != 0) {
        close(stdout_fd);
        close(stderr_fd);
        remove(stdout_template);
        remove(stderr_template);
        return 1;
    }

    pid_t child = fork();
    if (child < 0) {
        if (stdin_fd >= 0) {
            close(stdin_fd);
        }
        if (stdin_pipe[0] >= 0) {
            close(stdin_pipe[0]);
        }
        if (stdin_pipe[1] >= 0) {
            close(stdin_pipe[1]);
        }
        close(stdout_fd);
        close(stderr_fd);
        remove(stdout_template);
        remove(stderr_template);
        return 1;
    }

    if (child == 0) {
        if (working_directory != NULL && chdir(working_directory) != 0) {
            _exit(127);
        }
        if (envp != NULL) {
            for (size_t index = 0; envp[index] != NULL; index += 1) {
                putenv((char *)envp[index]);
            }
        }
        if (stdin_text != NULL) {
            if (dup2(stdin_pipe[0], STDIN_FILENO) < 0) {
                _exit(127);
            }
        } else if (stdin_fd >= 0) {
            if (dup2(stdin_fd, STDIN_FILENO) < 0) {
                _exit(127);
            }
        }
        if (dup2(stdout_fd, STDOUT_FILENO) < 0) {
            _exit(127);
        }
        if (dup2(stderr_fd, STDERR_FILENO) < 0) {
            _exit(127);
        }
        if (stdin_fd >= 0) {
            close(stdin_fd);
        }
        if (stdin_pipe[0] >= 0) {
            close(stdin_pipe[0]);
        }
        if (stdin_pipe[1] >= 0) {
            close(stdin_pipe[1]);
        }
        close(stdout_fd);
        close(stderr_fd);
        execvp(argv[0], (char *const *)argv);
        _exit(127);
    }

    if (stdin_fd >= 0) {
        close(stdin_fd);
    }
    if (stdin_pipe[0] >= 0) {
        close(stdin_pipe[0]);
    }
    if (stdin_pipe[1] >= 0) {
        if (ccc_write_all(stdin_pipe[1], stdin_text) != 0) {
            close(stdin_pipe[1]);
            close(stdout_fd);
            close(stderr_fd);
            waitpid(child, NULL, 0);
            remove(stdout_template);
            remove(stderr_template);
            return 1;
        }
        close(stdin_pipe[1]);
    }
    close(stdout_fd);
    close(stderr_fd);

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        remove(stdout_template);
        remove(stderr_template);
        return 1;
    }

    out_run->stdout_text = ccc_read_file(stdout_template);
    out_run->stderr_text = ccc_read_file(stderr_template);
    out_run->exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 1;

    if (out_run->stdout_text == NULL || out_run->stderr_text == NULL) {
        free(out_run->stdout_text);
        free(out_run->stderr_text);
        out_run->stdout_text = NULL;
        out_run->stderr_text = NULL;
        out_run->exit_code = 0;
        remove(stdout_template);
        remove(stderr_template);
        return 1;
    }

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
