#include <ccc/build_prompt.hpp>
#include <ccc/config.hpp>
#include <ccc/parser.hpp>
#include <ccc/runner.hpp>

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\"\n";
        return 1;
    }

    CommandSpec spec;

    if (argc == 2) {
        auto spec_opt = build_prompt_spec(argv[1]);
        if (!spec_opt.has_value()) {
            std::cerr << "prompt must not be empty\n";
            return 1;
        }
        spec = std::move(*spec_opt);
    } else {
        std::vector<std::string> args;
        args.reserve(static_cast<size_t>(argc - 1));
        for (int i = 1; i < argc; ++i) {
            args.emplace_back(argv[i]);
        }

        auto parsed = parseArgs(args);
        if (parsed.prompt.empty()) {
            std::cerr << "prompt must not be empty\n";
            return 1;
        }

        CccConfig config = loadDefaultConfig();

        try {
            auto [cmd_argv, env_overrides] = resolveCommand(parsed, &config);
            spec.argv = std::move(cmd_argv);
            spec.env = std::move(env_overrides);
        } catch (const std::exception& e) {
            std::cerr << e.what() << "\n";
            return 1;
        }
    }

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
