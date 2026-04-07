#pragma once

#include <ccc/parser.hpp>

#include <string>

CccConfig loadConfig(const std::string& path);
CccConfig loadDefaultConfig();
