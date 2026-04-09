import std/unittest
import std/strutils
import call_coding_clis/help

suite "help text":
  test "usage mentions name fallback":
    check usageText() == "usage: ccc [controls...] \"<Prompt>\""

  test "help explains preset then agent fallback":
    check "@name         Use a named preset from config; if no preset exists, treat it as an agent" in helpText()

  test "help lists selector remaps":
    check "opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)" in helpText()
