#ifndef CCC_RUNNER_H
#define CCC_RUNNER_H

typedef struct {
    int exit_code;
    char *stdout_text;
    char *stderr_text;
} ccc_completed_run;

int ccc_run_command(
    const char *const argv[],
    const char *stdin_text,
    const char *working_directory,
    const char *const envp[],
    ccc_completed_run *out_run
);

void ccc_free_completed_run(ccc_completed_run *run);

#endif
