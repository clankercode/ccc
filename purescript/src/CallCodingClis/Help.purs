module CallCodingClis.Help
  ( helpText
  , usageText
  , runnerChecklist
  ) where

import Prelude
import Effect (Effect)
import Data.Array (replicate, foldMap)
import Data.String (joinWith, length)
import Data.Traversable (traverse)

foreign import which :: String -> Effect Boolean
foreign import getVersion :: String -> Effect String

helpText :: String
helpText =
  "ccc — call coding CLIs\n"
    <> "\n"
    <> "Usage:\n"
    <> "  ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"\n"
    <> "  ccc --help\n"
    <> "  ccc -h\n"
    <> "\n"
    <> "Slots (in order):\n"
    <> "  runner        Select which coding CLI to use (default: oc)\n"
    <> "                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)\n"
    <> "  +thinking     Set thinking level: +0 (off) through +4 (max)\n"
    <> "  :provider:model  Override provider and model\n"
    <> "  @name         Use a named preset from config; if no preset exists, treat it as an agent\n"
    <> "\n"
    <> "Examples:\n"
    <> "  ccc \"Fix the failing tests\"\n"
    <> "  ccc oc \"Refactor auth module\"\n"
    <> "  ccc cc +2 :anthropic:claude-sonnet-4-20250514 \"Add tests\"\n"
    <> "  ccc k +4 \"Debug the parser\"\n"
    <> "  ccc @reviewer \"Audit the API boundary\"\n"
    <> "  ccc codex \"Write a unit test\"\n"
    <> "\n"
    <> "Config:\n"
    <> "  ~/.config/ccc/config.toml  — default runner, presets, abbreviations\n"

usageText :: String
usageText = "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""

type RunnerEntry =
  { name :: String
  , binary :: String
  }

runners :: Array RunnerEntry
runners =
  [ { name: "opencode", binary: "opencode" }
  , { name: "claude", binary: "claude" }
  , { name: "kimi", binary: "kimi" }
  , { name: "codex", binary: "codex" }
  , { name: "roocode", binary: "roocode" }
  , { name: "crush", binary: "crush" }
  ]

padName :: String -> String
padName name = name <> (joinWith "" $ replicate (10 - length name) " ")

runnerChecklist :: Effect String
runnerChecklist = do
  entries <- traverse checkRunner runners
  pure $ "Runners:\n" <> foldMap (\e -> e <> "\n") entries

checkRunner :: RunnerEntry -> Effect String
checkRunner { name, binary } = do
  found <- which binary
  if found then do
    ver <- getVersion binary
    let tag = if ver /= "" then ver else "found"
    pure $ "  [+] " <> padName name <> "(" <> binary <> ")  " <> tag
  else
    pure $ "  [-] " <> padName name <> "(" <> binary <> ")  not found"
