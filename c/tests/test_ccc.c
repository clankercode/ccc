#define _XOPEN_SOURCE 700

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static int run_cmd(const char *cmd) {
    int status = system(cmd);
    if (status == -1 || !WIFEXITED(status)) {
        return -1;
    }
    return WEXITSTATUS(status);
}

static int file_contains(const char *path, const char *needle) {
    FILE *fp = fopen(path, "r");
    if (fp == NULL) {
        return 0;
    }

    char buffer[4096];
    size_t nread = fread(buffer, 1, sizeof(buffer) - 1, fp);
    fclose(fp);
    buffer[nread] = '\0';
    return strstr(buffer, needle) != NULL;
}

static void write_fake_runner(const char *path) {
    FILE *fake_opencode = fopen(path, "w");
    if (fake_opencode == NULL) {
        fprintf(stderr, "failed to create fake runner\n");
        exit(1);
    }
    fprintf(fake_opencode, "#!/bin/sh\n");
    fprintf(fake_opencode, "agent=\n");
    fprintf(fake_opencode, "prompt=\n");
    fprintf(fake_opencode, "while [ \"$#\" -gt 0 ]; do\n");
    fprintf(fake_opencode, "  case \"$1\" in\n");
    fprintf(fake_opencode, "    --agent)\n");
    fprintf(fake_opencode, "      shift\n");
    fprintf(fake_opencode, "      agent=$1\n");
    fprintf(fake_opencode, "      ;;\n");
    fprintf(fake_opencode, "    --model|--effort|--think)\n");
    fprintf(fake_opencode, "      shift\n");
    fprintf(fake_opencode, "      ;;\n");
    fprintf(fake_opencode, "    --thinking)\n");
    fprintf(fake_opencode, "      if [ \"$2\" = \"enabled\" ] || [ \"$2\" = \"disabled\" ] || [ \"$2\" = \"adaptive\" ]; then\n");
    fprintf(fake_opencode, "        shift\n");
    fprintf(fake_opencode, "      fi\n");
    fprintf(fake_opencode, "      ;;\n");
    fprintf(fake_opencode, "    --no-thinking|--no-think|run)\n");
    fprintf(fake_opencode, "      ;;\n");
    fprintf(fake_opencode, "    *)\n");
    fprintf(fake_opencode, "      prompt=$1\n");
    fprintf(fake_opencode, "      ;;\n");
    fprintf(fake_opencode, "  esac\n");
    fprintf(fake_opencode, "  shift\n");
    fprintf(fake_opencode, "done\n");
    fprintf(fake_opencode, "if [ -n \"$agent\" ]; then\n");
    fprintf(fake_opencode, "  printf 'fake-stdout: %%s agent=%%s\\n' \"$prompt\" \"$agent\"\n");
    fprintf(fake_opencode, "  printf 'fake-stderr: %%s agent=%%s\\n' \"$prompt\" \"$agent\" >&2\n");
    fprintf(fake_opencode, "else\n");
    fprintf(fake_opencode, "  printf 'fake-stdout: %%s\\n' \"$prompt\"\n");
    fprintf(fake_opencode, "  printf 'fake-stderr: %%s\\n' \"$prompt\" >&2\n");
    fprintf(fake_opencode, "fi\n");
    fprintf(fake_opencode, "exit 42\n");
    fclose(fake_opencode);
    chmod(path, 0755);
}

static void join_path(char *out, size_t out_max, const char *left, const char *right) {
    size_t left_len = strlen(left);
    size_t right_len = strlen(right);
    if (left_len + right_len + 1 > out_max) {
        fprintf(stderr, "joined path too long\n");
        exit(1);
    }
    memcpy(out, left, left_len);
    memcpy(out + left_len, right, right_len + 1);
}

int main(void) {
    // Create a fake runner script that echoes prompt and agent state.
    write_fake_runner("./build/fake-runner");

    // Run ccc with the fake opencode via environment variable.
    int exit_code = run_cmd("CCC_REAL_OPENCODE=./build/fake-runner ./build/ccc 'Fix the failing tests' > ./build/output.txt 2> ./build/stderr.txt");

    // The fake opencode exits with 42, so ccc should too
    if (exit_code != 42) {
        fprintf(stderr, "unexpected exit code: %d (expected 42)\n", exit_code);
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

    if (strstr(buffer, "fake-stdout: Fix the failing tests") == NULL) {
        fprintf(stderr, "unexpected stdout: %s\n", buffer);
        return 1;
    }

    FILE *stderr_file = fopen("./build/stderr.txt", "r");
    if (stderr_file == NULL) {
        fprintf(stderr, "failed to open stderr file\n");
        return 1;
    }

    char stderr_buffer[256] = {0};
    fgets(stderr_buffer, sizeof(stderr_buffer), stderr_file);
    fclose(stderr_file);

    if (strstr(stderr_buffer, "fake-stderr: Fix the failing tests") == NULL) {
        fprintf(stderr, "unexpected stderr: %s\n", stderr_buffer);
        return 1;
    }

    // Help output should expose the new @name semantics.
    int help_status = run_cmd("./build/ccc --help > ./build/help.txt 2> ./build/help.err");
    if (help_status != 0) {
        fprintf(stderr, "--help should exit 0, got %d\n", help_status);
        return 1;
    }
    if (!file_contains("./build/help.txt", "ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"")) {
        fprintf(stderr, "help output missing @name usage line\n");
        return 1;
    }
    if (!file_contains("./build/help.txt", "codex (c/cx), roocode (rc)")) {
        fprintf(stderr, "help output missing remapped runner line\n");
        return 1;
    }
    if (!file_contains("./build/help.txt", "Use a named preset from config; if no preset exists, treat it as an agent")) {
        fprintf(stderr, "help output missing fallback explanation\n");
        return 1;
    }

    // Usage output should also mention @name when no prompt is supplied.
    int usage_status = run_cmd("./build/ccc > ./build/usage.txt 2> ./build/usage.err");
    if (usage_status != 1) {
        fprintf(stderr, "missing prompt should exit 1, got %d\n", usage_status);
        return 1;
    }
    if (!file_contains("./build/usage.err", "ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"")) {
        fprintf(stderr, "usage output missing @name usage line\n");
        return 1;
    }

    // Test missing prompt rejection
    int reject_code = run_cmd("./build/ccc '' > /dev/null 2>&1");
    if (reject_code != 1) {
        fprintf(stderr, "empty prompt should exit with code 1, got %d\n", reject_code);
        return 1;
    }

    // Test whitespace-only prompt rejection
    int ws_code = run_cmd("./build/ccc '   ' > /dev/null 2>&1");
    if (ws_code != 1) {
        fprintf(stderr, "whitespace-only prompt should exit with code 1, got %d\n", ws_code);
        return 1;
    }

    // Test prompt trimming: "  hello  " should be sent as "hello"
    int trim_exit = run_cmd("CCC_REAL_OPENCODE=./build/fake-runner ./build/ccc '  hello  ' > ./build/trim_output.txt 2> ./build/trim_stderr.txt");
    if (trim_exit != 42) {
        fprintf(stderr, "trimmed prompt test: unexpected exit code %d (expected 42)\n", trim_exit);
        return 1;
    }

    FILE *trim_out = fopen("./build/trim_output.txt", "r");
    if (trim_out == NULL) {
        fprintf(stderr, "failed to open trim output file\n");
        return 1;
    }
    char trim_buffer[256] = {0};
    fgets(trim_buffer, sizeof(trim_buffer), trim_out);
    fclose(trim_out);
    if (strstr(trim_buffer, "fake-stdout: hello") == NULL) {
        fprintf(stderr, "trimmed prompt not sent correctly: %s\n", trim_buffer);
        return 1;
    }

    // Agent fallback should pass through the requested @name on supported runners.
    int fallback_status = run_cmd("CCC_REAL_OPENCODE=./build/fake-runner ./build/ccc '@reviewer' 'Fix the failing tests' > ./build/agent_output.txt 2> ./build/agent.err");
    if (fallback_status != 42) {
        fprintf(stderr, "agent fallback test: unexpected exit code %d\n", fallback_status);
        return 1;
    }
    if (!file_contains("./build/agent_output.txt", "agent=reviewer")) {
        fprintf(stderr, "agent fallback not applied\n");
        return 1;
    }

    // Preset agents should override the name fallback when present in config.
    char xdg_template[] = "./build/ccc-cli-xdg-XXXXXX";
    char *xdg_root = mkdtemp(xdg_template);
    if (xdg_root == NULL) {
        fprintf(stderr, "failed to create xdg temp dir\n");
        return 1;
    }
    char xdg_config_dir[512];
    join_path(xdg_config_dir, sizeof(xdg_config_dir), xdg_root, "/ccc");
    if (mkdir(xdg_config_dir, 0700) != 0) {
        fprintf(stderr, "failed to create xdg config dir\n");
        return 1;
    }
    char xdg_config_file[512];
    join_path(xdg_config_file, sizeof(xdg_config_file), xdg_config_dir, "/config.toml");
    FILE *config = fopen(xdg_config_file, "w");
    if (config == NULL) {
        fprintf(stderr, "failed to write preset config\n");
        return 1;
    }
    fputs("[aliases.reviewer]\nagent = \"specialist\"\n", config);
    fclose(config);
    char preset_cmd[1024];
    snprintf(
        preset_cmd,
        sizeof(preset_cmd),
        "HOME=./build/ccc-home-unused XDG_CONFIG_HOME=%s CCC_REAL_OPENCODE=./build/fake-runner "
        "./build/ccc '@reviewer' 'Fix the failing tests' > ./build/preset_output.txt 2> ./build/preset.err",
        xdg_root
    );
    int preset_status = run_cmd(preset_cmd);
    if (preset_status != 42) {
        fprintf(stderr, "preset agent test: unexpected exit code %d\n", preset_status);
        return 1;
    }
    if (!file_contains("./build/preset_output.txt", "agent=specialist")) {
        fprintf(stderr, "preset agent not applied\n");
        return 1;
    }

    // Unsupported agent support should warn and ignore the agent flag.
    int warn_status = run_cmd(
        "CCC_REAL_OPENCODE=./build/fake-runner ./build/ccc rc '@reviewer' 'Fix the failing tests' > ./build/warn_out.txt 2> ./build/warn.err"
    );
    if (warn_status != 42) {
        fprintf(stderr, "unsupported-agent test: unexpected exit code %d\n", warn_status);
        return 1;
    }
    if (!file_contains("./build/warn.err", "runner \"roocode\" does not support agents; ignoring @reviewer")) {
        fprintf(stderr, "unsupported-agent warning missing: ");
        FILE *warn = fopen("./build/warn.err", "r");
        if (warn != NULL) {
            char warn_buf[256] = {0};
            fgets(warn_buf, sizeof(warn_buf), warn);
            fclose(warn);
            fprintf(stderr, "%s\n", warn_buf);
        } else {
            fprintf(stderr, "(unable to read warning output)\n");
        }
        return 1;
    }

    return 0;
}
