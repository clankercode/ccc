#pragma once

#include <string>
#include <vector>

struct CompletedRun {
    std::vector<std::string> argv;
    int exit_code = 0;
    std::string out_stdout;
    std::string out_stderr;
};
