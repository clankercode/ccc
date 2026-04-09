module Test.Main where

import Prelude

import CallCodingClis.Config (defaultConfig, parseConfig)
import CallCodingClis.Help (helpText, usageText)
import CallCodingClis.Parser (parseArgs, resolveCommand, resolveRunnerName)
import CallCodingClis.PromptSpec (buildPromptSpec)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String.CodeUnits as CU
import Data.String.Pattern (Pattern(..))
import Effect (Effect)
import Effect.Console (log)
import Foreign.Object as Object
import Node.Process (exit')

check :: String -> Boolean -> Effect Boolean
check name passed = do
  log $ (if passed then "PASS: " else "FAIL: ") <> name
  pure passed

main :: Effect Unit
main = do
  r1 <- check "buildPromptSpec: valid prompt" $
    case buildPromptSpec "Fix the failing tests" of
      Right spec -> spec.argv == ["opencode", "run", "Fix the failing tests"]
      Left _ -> false

  r2 <- check "buildPromptSpec: empty prompt rejected" $
    case buildPromptSpec "" of
      Left msg -> msg == "prompt must not be empty"
      Right _ -> false

  r3 <- check "buildPromptSpec: whitespace prompt rejected" $
    case buildPromptSpec "   " of
      Left _ -> true
      Right _ -> false

  r4 <- check "buildPromptSpec: prompt trimmed" $
    case buildPromptSpec "  hello  " of
      Right spec -> spec.argv == ["opencode", "run", "hello"]
      Left _ -> false

  r5 <- check "buildPromptSpec: tabs and newlines trimmed" $
    case buildPromptSpec "\t\nmixed whitespace \n" of
      Right spec -> spec.argv == ["opencode", "run", "mixed whitespace"]
      Left _ -> false

  r6 <- check "buildPromptSpec: stdinText is Nothing" $
    case buildPromptSpec "Fix the failing tests" of
      Right spec -> spec.stdinText == Nothing
      Left _ -> false

  r7 <- check "buildPromptSpec: cwd is Nothing" $
    case buildPromptSpec "Fix the failing tests" of
      Right spec -> spec.cwd == Nothing
      Left _ -> false

  r8 <- check "parseArgs recognizes cx as a runner selector" $
    let parsed = parseArgs [ "cx", "Fix the failing tests" ]
        resolved = resolveCommand parsed (defaultConfig { defaultRunner = "oc" })
    in parsed.runner == Just "cx"
      && parsed.prompt == "Fix the failing tests"
      && resolved.argv == ["codex", "exec", "Fix the failing tests"]

  r9 <- check "resolveRunnerName remaps c/cx/cc/rc" $
    resolveRunnerName "c" defaultConfig == "codex"
      && resolveRunnerName "cx" defaultConfig == "codex"
      && resolveRunnerName "cc" defaultConfig == "claude"
      && resolveRunnerName "rc" defaultConfig == "roocode"

  r10 <- check "usageText uses @name" $
    usageText == "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""

  r11 <- check "helpText explains selector remap and preset-then-agent fallback" $
    CU.indexOf (Pattern "[@name]") helpText /= Nothing
      && CU.indexOf (Pattern "claude (cc)") helpText /= Nothing
      && CU.indexOf (Pattern "codex (c/cx)") helpText /= Nothing
      && CU.indexOf (Pattern "roocode (rc)") helpText /= Nothing
      && CU.indexOf (Pattern "if no preset exists, treat it as an agent") helpText /= Nothing

  let configText =
        "[defaults]\n"
          <> "runner = \"cc\"\n"
          <> "provider = \"anthropic\"\n"
          <> "model = \"claude-4\"\n"
          <> "thinking = 2\n"
          <> "\n"
          <> "[abbreviations]\n"
          <> "mycc = \"cc\"\n"
          <> "\n"
          <> "[aliases.work]\n"
          <> "runner = \"cc\"\n"
          <> "thinking = 3\n"
          <> "provider = \"anthropic\"\n"
          <> "model = \"claude-4\"\n"
          <> "agent = \"reviewer\"\n"

  let parsedConfig = parseConfig configText
  r12 <- check "parseConfig loads defaults, abbreviations, and agent" $
    parsedConfig.defaultRunner == "cc"
      && parsedConfig.defaultProvider == "anthropic"
      && parsedConfig.defaultModel == "claude-4"
      && parsedConfig.defaultThinking == Just 2
          && Object.lookup "mycc" parsedConfig.abbreviations == Just "cc"
          && Object.lookup "work" parsedConfig.aliases
        == Just
          { runner: Just "cc"
          , thinking: Just 3
          , provider: Just "anthropic"
          , model: Just "claude-4"
          , agent: Just "reviewer"
          }

  let agentFallbackConfig = defaultConfig { defaultRunner = "oc" }
  r13 <- check "resolveCommand falls back to agent when preset is absent" $
    let resolved =
          resolveCommand
            { runner: Nothing
            , thinking: Nothing
            , provider: Nothing
            , model: Nothing
            , alias: Just "reviewer"
            , prompt: "Fix the failing tests"
            }
            agentFallbackConfig
    in resolved.argv
        == ["opencode", "run", "--agent", "reviewer", "Fix the failing tests"]
        && Object.isEmpty resolved.env
        && resolved.warnings == []

  let presetAgentConfig =
        defaultConfig
          { aliases =
              Object.insert
                "work"
                { runner: Nothing
                , thinking: Nothing
                , provider: Nothing
                , model: Nothing
                , agent: Just "specialist"
                }
                Object.empty
          }
  r14 <- check "resolveCommand uses preset agent over fallback" $
    let resolved =
          resolveCommand
            { runner: Nothing
            , thinking: Nothing
            , provider: Nothing
            , model: Nothing
            , alias: Just "work"
            , prompt: "Fix the failing tests"
            }
            presetAgentConfig
    in resolved.argv
        == ["opencode", "run", "--agent", "specialist", "Fix the failing tests"]
        && resolved.warnings == []

  let unsupportedAgentConfig = defaultConfig { defaultRunner = "rc" }
  r15 <- check "resolveCommand warns when runner lacks agent support" $
    let resolved =
          resolveCommand
            { runner: Nothing
            , thinking: Nothing
            , provider: Nothing
            , model: Nothing
            , alias: Just "reviewer"
            , prompt: "Fix the failing tests"
            }
            unsupportedAgentConfig
    in resolved.argv == ["roocode", "Fix the failing tests"]
      && resolved.warnings
        == [ "warning: runner \"roocode\" does not support agents; ignoring @reviewer"
           ]

  let allPassed = r1 && r2 && r3 && r4 && r5 && r6 && r7 && r8 && r9 && r10 && r11 && r12 && r13 && r14 && r15
  if allPassed then pure unit else exit' 1
