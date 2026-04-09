import std/options
import std/os
import std/tables
import std/unittest
import call_coding_clis/config

suite "loadConfig":
  test "missing file returns defaults":
    let configPath = getTempDir() / "ccc-nim-missing-config.toml"
    let cfg = loadConfig(some(configPath))
    check cfg.defaultRunner == "oc"
    check cfg.aliases.len == 0

  test "parses toml config with agent preset":
    let configPath = getTempDir() / "ccc-nim-config.toml"
    writeFile(
      configPath,
      """
[defaults]
runner = "claude"
provider = "anthropic"
model = "claude-4"
thinking = 2

[abbreviations]
mycc = "cc"

[aliases.work]
runner = "cc"
thinking = 3
model = "claude-4"
agent = "reviewer"

[aliases.quick]
runner = "oc"
"""
    )

    let cfg = loadConfig(some(configPath))
    check cfg.defaultRunner == "claude"
    check cfg.defaultProvider == "anthropic"
    check cfg.defaultModel == "claude-4"
    check cfg.defaultThinking == some(2)
    check cfg.abbreviations["mycc"] == "cc"
    check cfg.aliases["work"].runner == some("cc")
    check cfg.aliases["work"].thinking == some(3)
    check cfg.aliases["work"].model == some("claude-4")
    check cfg.aliases["work"].agent == some("reviewer")
    check cfg.aliases["quick"].runner == some("oc")
