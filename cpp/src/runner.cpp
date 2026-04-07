#include <ccc/runner.hpp>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <map>
#include <poll.h>
#include <sstream>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <utility>
#include <vector>

extern char** environ;

namespace {

class Fd {
    int fd_;
public:
    explicit Fd(int fd = -1) noexcept : fd_(fd) {}
    ~Fd() { if (fd_ >= 0) ::close(fd_); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
    Fd(Fd&& o) noexcept : fd_(std::exchange(o.fd_, -1)) {}
    Fd& operator=(Fd&& o) noexcept {
        if (this != &o) {
            if (fd_ >= 0) ::close(fd_);
            fd_ = std::exchange(o.fd_, -1);
        }
        return *this;
    }
    int get() const noexcept { return fd_; }
    explicit operator bool() const noexcept { return fd_ >= 0; }
};

bool write_all(int fd, const std::string& data) {
    size_t remaining = data.size();
    const char* cursor = data.data();
    while (remaining > 0) {
        ssize_t written = ::write(fd, cursor, remaining);
        if (written < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        if (written == 0) return false;
        cursor += written;
        remaining -= static_cast<size_t>(written);
    }
    return true;
}

std::pair<std::string, std::string> read_pipes(int stdout_fd, int stderr_fd) {
    std::string out, err;
    std::array<char, 4096> buf;
    struct pollfd fds[2] = {{stdout_fd, POLLIN, 0}, {stderr_fd, POLLIN, 0}};

    while (fds[0].fd >= 0 || fds[1].fd >= 0) {
        int ready = ::poll(fds, 2, -1);
        if (ready < 0) {
            if (errno == EINTR) continue;
            break;
        }
        for (int i = 0; i < 2; ++i) {
            if (fds[i].fd < 0) continue;
            if (fds[i].revents & (POLLIN | POLLHUP)) {
                ssize_t n = ::read(fds[i].fd, buf.data(), buf.size());
                if (n > 0) {
                    (i == 0 ? out : err).append(buf.data(), static_cast<size_t>(n));
                } else {
                    fds[i].fd = -1;
                }
            }
            if (fds[i].revents & (POLLERR | POLLNVAL)) {
                fds[i].fd = -1;
            }
        }
    }
    return {std::move(out), std::move(err)};
}

std::vector<std::string> make_env_array(const std::map<std::string, std::string>& overrides) {
    std::vector<std::string> result;
    if (overrides.empty()) return result;
    for (size_t i = 0; environ[i] != nullptr; ++i) {
        std::string entry = environ[i];
        auto eq = entry.find('=');
        if (eq == std::string::npos) continue;
        auto key = entry.substr(0, eq);
        if (overrides.count(key)) continue;
        result.push_back(std::move(entry));
    }
    for (const auto& [k, v] : overrides) {
        result.push_back(k + "=" + v);
    }
    return result;
}

std::vector<char*> to_c_argv(const std::vector<std::string>& args) {
    std::vector<char*> result;
    result.reserve(args.size() + 1);
    for (auto& s : args) {
        result.push_back(const_cast<char*>(s.c_str()));
    }
    result.push_back(nullptr);
    return result;
}

std::vector<char*> to_c_envp(std::vector<std::string>& env_strings) {
    std::vector<char*> result;
    result.reserve(env_strings.size() + 1);
    for (auto& s : env_strings) {
        result.push_back(const_cast<char*>(s.c_str()));
    }
    result.push_back(nullptr);
    return result;
}

CompletedRun failed_run(const std::vector<std::string>& argv, const std::string& error) {
    return CompletedRun{
        argv,
        1,
        std::string(),
        "failed to start " + argv[0] + ": " + error + "\n"
    };
}

CompletedRun default_executor(const CommandSpec& spec) {
    if (spec.argv.empty() || spec.argv[0].empty()) {
        return CompletedRun{spec.argv, 1, {}, "failed to start : empty command\n"};
    }

    int stdin_pipe[2] = {-1, -1};
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};

    if (::pipe(stdout_pipe) != 0) {
        return failed_run(spec.argv, std::strerror(errno));
    }
    Fd stdout_rd(stdout_pipe[0]);
    Fd stdout_wr(stdout_pipe[1]);

    if (::pipe(stderr_pipe) != 0) {
        return failed_run(spec.argv, std::strerror(errno));
    }
    Fd stderr_rd(stderr_pipe[0]);
    Fd stderr_wr(stderr_pipe[1]);

    Fd stdin_rd_parent;
    if (spec.stdin_text.has_value()) {
        if (::pipe(stdin_pipe) != 0) {
            return failed_run(spec.argv, std::strerror(errno));
        }
        stdin_rd_parent = Fd(stdin_pipe[1]);
    }

    pid_t pid = ::fork();
    if (pid < 0) {
        return failed_run(spec.argv, std::strerror(errno));
    }

    if (pid == 0) {
        int devnull = ::open("/dev/null", O_RDONLY);
        if (spec.stdin_text.has_value()) {
            ::dup2(stdin_pipe[0], STDIN_FILENO);
        } else if (devnull >= 0) {
            ::dup2(devnull, STDIN_FILENO);
        }
        if (devnull >= 0) ::close(devnull);

        ::dup2(stdout_wr.get(), STDOUT_FILENO);
        ::dup2(stderr_wr.get(), STDERR_FILENO);

        if (spec.stdin_text.has_value()) ::close(stdin_pipe[0]);
        stdout_wr = Fd();
        stderr_wr = Fd();
        stdin_rd_parent = Fd();

        if (spec.cwd.has_value()) {
            if (::chdir(spec.cwd->c_str()) != 0) {
                ::_exit(127);
            }
        }

        auto c_argv = to_c_argv(spec.argv);

        if (!spec.env.empty()) {
            auto env_strings = make_env_array(spec.env);
            auto c_envp = to_c_envp(env_strings);
            ::execve(c_argv[0], c_argv.data(), c_envp.data());
        } else {
            ::execvp(c_argv[0], c_argv.data());
        }

        ::dprintf(STDERR_FILENO, "failed to start %s: %s\n", c_argv[0], std::strerror(errno));
        ::_exit(127);
    }

    Fd child_stdin_rd;
    if (spec.stdin_text.has_value()) {
        child_stdin_rd = Fd(stdin_pipe[0]);
    }
    stdout_wr = Fd();
    stderr_wr = Fd();

    if (spec.stdin_text.has_value()) {
        if (!write_all(stdin_rd_parent.get(), *spec.stdin_text)) {
            stdin_rd_parent = Fd();
            int status = 0;
            while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
            auto [out, err] = read_pipes(stdout_rd.get(), stderr_rd.get());
            int ec = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
            return CompletedRun{spec.argv, ec, std::move(out), std::move(err)};
        }
    }
    stdin_rd_parent = Fd();

    auto [out, err] = read_pipes(stdout_rd.get(), stderr_rd.get());

    int status = 0;
    while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {}

    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    return CompletedRun{spec.argv, exit_code, std::move(out), std::move(err)};
}

}  // namespace

Runner::Runner() : executor_(default_executor) {}

Runner::Runner(std::function<CompletedRun(const CommandSpec&)> executor)
    : executor_(std::move(executor)) {}

Runner::Runner(Runner&& o) noexcept = default;
Runner& Runner::operator=(Runner&& o) noexcept = default;

CompletedRun Runner::run(const CommandSpec& spec) {
    return executor_(spec);
}

CompletedRun Runner::stream(const CommandSpec& spec, StreamCallback on_event) {
    CompletedRun result = executor_(spec);
    if (!result.out_stdout.empty()) {
        on_event("stdout", result.out_stdout);
    }
    if (!result.out_stderr.empty()) {
        on_event("stderr", result.out_stderr);
    }
    return result;
}
