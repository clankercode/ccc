#include <gtest/gtest.h>

#include <array>
#include <cstdlib>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>
#include <unistd.h>
#include <sys/wait.h>

namespace fs = std::filesystem;

static fs::path find_ccc_binary() {
    fs::path self = fs::read_symlink("/proc/self/exe");
    return self.parent_path().parent_path() / "ccc";
}

static fs::path write_opencode_stub(const fs::path& dir) {
    auto stub = dir / "opencode";
    std::ofstream f(stub);
    f << "#!/bin/sh\n"
      << "if [ \"$1\" != \"run\" ]; then exit 9; fi\n"
      << "shift\n"
      << "agent=\"\"\n"
      << "if [ \"$1\" = \"--agent\" ]; then\n"
      << "  agent=\"$2\"\n"
      << "  shift 2\n"
      << "fi\n"
      << "if [ -n \"$agent\" ]; then\n"
      << "  printf 'opencode run --agent %s %s\\n' \"$agent\" \"$1\"\n"
      << "else\n"
      << "  printf 'opencode run %s\\n' \"$1\"\n"
      << "fi\n";
    f.close();
    fs::permissions(stub,
        fs::perms::owner_exec | fs::perms::group_exec | fs::perms::others_exec,
        fs::perm_options::add);
    return stub;
}

static fs::path write_codex_stub(const fs::path& dir) {
    auto stub = dir / "codex";
    std::ofstream f(stub);
    f << "#!/bin/sh\n"
      << "if [ \"$1\" != \"exec\" ]; then exit 9; fi\n"
      << "shift\n"
      << "printf 'codex exec %s\\n' \"$1\"\n";
    f.close();
    fs::permissions(stub,
        fs::perms::owner_exec | fs::perms::group_exec | fs::perms::others_exec,
        fs::perm_options::add);
    return stub;
}

static fs::path write_roocode_stub(const fs::path& dir) {
    auto stub = dir / "roocode";
    std::ofstream f(stub);
    f << "#!/bin/sh\n"
      << "printf 'roocode %s\\n' \"$1\"\n";
    f.close();
    fs::permissions(stub,
        fs::perms::owner_exec | fs::perms::group_exec | fs::perms::others_exec,
        fs::perm_options::add);
    return stub;
}

static void write_config_with_agent(const fs::path& root) {
    auto config_dir = root / ".config" / "ccc";
    fs::create_directories(config_dir);
    std::ofstream f(config_dir / "config.toml");
    f << "[aliases.reviewer]\n"
      << "agent = \"specialist\"\n";
}

struct SubprocessResult {
    int exit_code;
    std::string stdout_text;
    std::string stderr_text;
};

static SubprocessResult run_ccc(const fs::path& ccc_bin,
                                const std::vector<std::string>& args,
                                const std::vector<std::pair<std::string, std::string>>& extra_env = {}) {
    int stdout_pipe[2], stderr_pipe[2];
    if (::pipe(stdout_pipe) != 0 || ::pipe(stderr_pipe) != 0) {
        return {-1, "", "pipe failed"};
    }

    pid_t pid = ::fork();
    if (pid < 0) {
        ::close(stdout_pipe[0]); ::close(stdout_pipe[1]);
        ::close(stderr_pipe[0]); ::close(stderr_pipe[1]);
        return {-1, "", "fork failed"};
    }

    if (pid == 0) {
        ::dup2(stdout_pipe[1], STDOUT_FILENO);
        ::dup2(stderr_pipe[1], STDERR_FILENO);
        ::close(stdout_pipe[0]); ::close(stdout_pipe[1]);
        ::close(stderr_pipe[0]); ::close(stderr_pipe[1]);

        for (const auto& [k, v] : extra_env) {
            ::setenv(k.c_str(), v.c_str(), 1);
        }

        std::vector<char*> argv;
        argv.push_back(const_cast<char*>(ccc_bin.c_str()));
        for (const auto& a : args) {
            argv.push_back(const_cast<char*>(a.c_str()));
        }
        argv.push_back(nullptr);

        ::execvp(argv[0], argv.data());
        ::_exit(127);
    }

    ::close(stdout_pipe[1]);
    ::close(stderr_pipe[1]);

    std::string stdout_text, stderr_text;
    std::array<char, 4096> buf;
    ssize_t n;
    while ((n = ::read(stdout_pipe[0], buf.data(), buf.size())) > 0) {
        stdout_text.append(buf.data(), static_cast<size_t>(n));
    }
    ::close(stdout_pipe[0]);
    while ((n = ::read(stderr_pipe[0], buf.data(), buf.size())) > 0) {
        stderr_text.append(buf.data(), static_cast<size_t>(n));
    }
    ::close(stderr_pipe[0]);

    int status = 0;
    while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 1;

    return {exit_code, stdout_text, stderr_text};
}

struct CccContract : ::testing::Test {
    fs::path ccc_bin;
    fs::path tmp_dir;

    void SetUp() override {
        ccc_bin = find_ccc_binary();
        tmp_dir = fs::temp_directory_path() / "ccc-cpp-test-XXXXXX";
        fs::create_directories(tmp_dir);
    }

    void TearDown() override {
        std::error_code ec;
        fs::remove_all(tmp_dir, ec);
    }
};

TEST_F(CccContract, HappyPath) {
    auto stub = write_opencode_stub(tmp_dir);
    auto result = run_ccc(ccc_bin, {"Fix the failing tests"}, {
        {"CCC_REAL_OPENCODE", stub.string()},
        {"HOME", tmp_dir.string()},
        {"XDG_CONFIG_HOME", (tmp_dir / "xdg").string()},
    });
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.stdout_text, "opencode run Fix the failing tests\n");
}

TEST_F(CccContract, NameFallsBackToAgent) {
    auto stub = write_opencode_stub(tmp_dir);
    auto result = run_ccc(ccc_bin, {"@reviewer", "Fix the failing tests"}, {
        {"CCC_REAL_OPENCODE", stub.string()},
        {"HOME", tmp_dir.string()},
        {"XDG_CONFIG_HOME", (tmp_dir / "xdg").string()},
    });
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.stdout_text, "opencode run --agent reviewer Fix the failing tests\n");
    EXPECT_TRUE(result.stderr_text.empty());
}

TEST_F(CccContract, PresetAgentWinsOverNameFallback) {
    auto stub = write_opencode_stub(tmp_dir);
    write_config_with_agent(tmp_dir);
    auto result = run_ccc(ccc_bin, {"@reviewer", "Fix the failing tests"}, {
        {"CCC_REAL_OPENCODE", stub.string()},
        {"HOME", tmp_dir.string()},
        {"XDG_CONFIG_HOME", (tmp_dir / "xdg").string()},
    });
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.stdout_text, "opencode run --agent specialist Fix the failing tests\n");
    EXPECT_TRUE(result.stderr_text.empty());
}

TEST_F(CccContract, RunnerCAliasesToCodex) {
    write_codex_stub(tmp_dir);
    std::string path = tmp_dir.string();
    if (const char* existing_path = std::getenv("PATH")) {
        path += ":";
        path += existing_path;
    }
    auto result = run_ccc(ccc_bin, {"c", "Fix the failing tests"}, {
        {"PATH", path},
        {"HOME", tmp_dir.string()},
        {"XDG_CONFIG_HOME", (tmp_dir / "xdg").string()},
    });
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.stdout_text, "codex exec Fix the failing tests\n");
    EXPECT_TRUE(result.stderr_text.empty());
}

TEST_F(CccContract, RunnerCxAliasesToCodex) {
    write_codex_stub(tmp_dir);
    std::string path = tmp_dir.string();
    if (const char* existing_path = std::getenv("PATH")) {
        path += ":";
        path += existing_path;
    }
    auto result = run_ccc(ccc_bin, {"cx", "Fix the failing tests"}, {
        {"PATH", path},
        {"HOME", tmp_dir.string()},
        {"XDG_CONFIG_HOME", (tmp_dir / "xdg").string()},
    });
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.stdout_text, "codex exec Fix the failing tests\n");
    EXPECT_TRUE(result.stderr_text.empty());
}

TEST_F(CccContract, UnsupportedAgentWarnsAndIsIgnored) {
    write_roocode_stub(tmp_dir);
    std::string path = tmp_dir.string();
    if (const char* existing_path = std::getenv("PATH")) {
        path += ":";
        path += existing_path;
    }
    auto result = run_ccc(ccc_bin, {"rc", "@reviewer", "Fix the failing tests"}, {
        {"PATH", path},
        {"HOME", tmp_dir.string()},
        {"XDG_CONFIG_HOME", (tmp_dir / "xdg").string()},
    });
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.stdout_text, "roocode Fix the failing tests\n");
    EXPECT_NE(result.stderr_text.find("warning: runner \"rc\" does not support agents; ignoring @reviewer"),
              std::string::npos);
}

TEST_F(CccContract, HelpSurfaceMentionsNameSlot) {
    auto result = run_ccc(ccc_bin, {"--help"});
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_NE(result.stdout_text.find("[@name]"), std::string::npos);
    EXPECT_NE(result.stdout_text.find("if no preset exists, treat it as an agent"), std::string::npos);
}

TEST_F(CccContract, EmptyPrompt) {
    auto result = run_ccc(ccc_bin, {""});
    EXPECT_EQ(result.exit_code, 1);
    EXPECT_TRUE(result.stdout_text.empty());
    EXPECT_FALSE(result.stderr_text.empty());
}

TEST_F(CccContract, MissingPrompt) {
    auto result = run_ccc(ccc_bin, {});
    EXPECT_EQ(result.exit_code, 1);
    EXPECT_NE(result.stderr_text.find("usage: ccc"), std::string::npos);
}

TEST_F(CccContract, WhitespacePrompt) {
    auto result = run_ccc(ccc_bin, {"   "});
    EXPECT_EQ(result.exit_code, 1);
    EXPECT_TRUE(result.stdout_text.empty());
    EXPECT_FALSE(result.stderr_text.empty());
}
