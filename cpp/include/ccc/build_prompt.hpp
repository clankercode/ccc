#pragma once

#include <ccc/command_spec.hpp>

#include <optional>
#include <string_view>

std::optional<CommandSpec> build_prompt_spec(std::string_view prompt);
