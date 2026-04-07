#include <gtest/gtest.h>

#include <array>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <system_error>
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
      << "printf 'opencode run %s\\n' \"$1\"\n";
    f.close();
    fs::permissions(stub,
        fs::perms::owner_exec | fs::perms::group_exec | fs::perms::others_exec,
        fs::perm_options::add);
    return stub;
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
        {"CCC_REAL_OPENCODE", stub.string()}
    });
    EXPECT_EQ(result.exit_code, 0);
    EXPECT_EQ(result.stdout_text, "opencode run Fix the failing tests\n");
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
    EXPECT_NE(result.stderr_text.find("ccc \"<Prompt>\""), std::string::npos);
}

TEST_F(CccContract, WhitespacePrompt) {
    auto result = run_ccc(ccc_bin, {"   "});
    EXPECT_EQ(result.exit_code, 1);
    EXPECT_TRUE(result.stdout_text.empty());
    EXPECT_FALSE(result.stderr_text.empty());
}
