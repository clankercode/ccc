#include <ccc/build_prompt.hpp>
#include <ccc/runner.hpp>

#include <cstdlib>
#include <iostream>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "usage: ccc \"<Prompt>\"\n";
        return 1;
    }

    auto spec_opt = build_prompt_spec(argv[1]);
    if (!spec_opt.has_value()) {
        std::cerr << "prompt must not be empty\n";
        return 1;
    }

    auto& spec = spec_opt.value();

    const char* real_opencode = std::getenv("CCC_REAL_OPENCODE");
    if (real_opencode != nullptr) {
        spec.argv[0] = real_opencode;
    }

    Runner runner;
    auto result = runner.run(spec);

    if (!result.out_stdout.empty()) {
        std::cout << result.out_stdout;
    }
    if (!result.out_stderr.empty()) {
        std::cerr << result.out_stderr;
    }

    std::exit(result.exit_code);
}
