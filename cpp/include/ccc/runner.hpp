#pragma once

#include <ccc/command_spec.hpp>
#include <ccc/completed_run.hpp>

#include <functional>
#include <string_view>

using StreamCallback = std::function<void(std::string_view stream_name, std::string_view data)>;

class Runner {
public:
    Runner();
    explicit Runner(std::function<CompletedRun(const CommandSpec&)> executor);

    Runner(const Runner&) = delete;
    Runner& operator=(const Runner&) = delete;

    Runner(Runner&&) noexcept;
    Runner& operator=(Runner&&) noexcept;

    CompletedRun run(const CommandSpec& spec);
    CompletedRun stream(const CommandSpec& spec, StreamCallback on_event);

private:
    std::function<CompletedRun(const CommandSpec&)> executor_;
};
