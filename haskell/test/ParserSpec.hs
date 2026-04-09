module ParserSpec (parserSpec) where

import CallCodingClis.Parser
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Test.Hspec

parserSpec :: Spec
parserSpec = do
  describe "parseArgs" $ do
    it "parses prompt-only" $ do
      let r = parseArgs ["hello"]
      paRunner r `shouldBe` Nothing
      paThinking r `shouldBe` Nothing
      paProvider r `shouldBe` Nothing
      paModel r `shouldBe` Nothing
      paAlias r `shouldBe` Nothing
      paPrompt r `shouldBe` "hello"

    it "parses runner selector" $ do
      let r = parseArgs ["claude", "hello"]
      paRunner r `shouldBe` Just "claude"
      paPrompt r `shouldBe` "hello"

    it "parses runner abbreviation" $ do
      let r = parseArgs ["cc", "hello"]
      paRunner r `shouldBe` Just "cc"

    it "parses codex selector c" $ do
      let r = parseArgs ["c", "hello"]
      paRunner r `shouldBe` Just "c"

    it "parses codex selector cx" $ do
      let r = parseArgs ["cx", "hello"]
      paRunner r `shouldBe` Just "cx"

    it "parses roocode selector rc" $ do
      let r = parseArgs ["rc", "hello"]
      paRunner r `shouldBe` Just "rc"

    it "parses thinking flag" $ do
      let r = parseArgs ["+3", "hello"]
      paThinking r `shouldBe` Just 3
      paPrompt r `shouldBe` "hello"

    it "parses provider:model" $ do
      let r = parseArgs [":anthropic:claude-3", "hello"]
      paProvider r `shouldBe` Just "anthropic"
      paModel r `shouldBe` Just "claude-3"

    it "parses model only" $ do
      let r = parseArgs [":claude-3-opus", "hello"]
      paModel r `shouldBe` Just "claude-3-opus"

    it "parses alias" $ do
      let r = parseArgs ["@fast", "hello"]
      paAlias r `shouldBe` Just "fast"

    it "parses full combo" $ do
      let r = parseArgs ["claude", "+2", ":anthropic:opus", "@fast", "fix", "bug"]
      paRunner r `shouldBe` Just "claude"
      paThinking r `shouldBe` Just 2
      paProvider r `shouldBe` Just "anthropic"
      paModel r `shouldBe` Just "opus"
      paAlias r `shouldBe` Just "fast"
      paPrompt r `shouldBe` "fix bug"

    it "lowercases runner selector" $ do
      let r = parseArgs ["Claude", "hello"]
      paRunner r `shouldBe` Just "claude"

    it "positional tokens stop special parsing" $ do
      let r = parseArgs ["hello", "claude"]
      paRunner r `shouldBe` Nothing
      paPrompt r `shouldBe` "hello claude"

    it "rejects thinking +5 (not 0-4)" $ do
      let r = parseArgs ["+5", "hello"]
      paThinking r `shouldBe` Nothing
      paPrompt r `shouldBe` "+5 hello"

  describe "resolveCommand" $ do
    it "uses default runner (opencode)" $ do
      let parsed = ParsedArgs Nothing Nothing Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["opencode", "run", "hello"], Map.empty, [])

    it "uses claude runner" $ do
      let parsed = ParsedArgs (Just "claude") Nothing Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["claude", "hello"], Map.empty, [])

    it "uses claude abbreviation" $ do
      let parsed = ParsedArgs (Just "cc") Nothing Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["claude", "hello"], Map.empty, [])

    it "uses codex runner for c selector" $ do
      let parsed = ParsedArgs (Just "c") Nothing Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["codex", "hello"], Map.empty, [])

    it "uses codex runner for cx selector" $ do
      let parsed = ParsedArgs (Just "cx") Nothing Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["codex", "hello"], Map.empty, [])

    it "uses roocode runner for rc selector" $ do
      let parsed = ParsedArgs (Just "rc") Nothing Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["roocode", "hello"], Map.empty, [])

    it "adds thinking flags for claude" $ do
      let parsed = ParsedArgs (Just "claude") (Just 3) Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["claude", "--thinking", "enabled", "--effort", "high", "hello"], Map.empty, [])

    it "adds model flag for claude" $ do
      let parsed = ParsedArgs (Just "claude") Nothing Nothing (Just "opus") Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["claude", "--model", "opus", "hello"], Map.empty, [])

    it "sets CCC_PROVIDER env for provider" $ do
      let parsed = ParsedArgs Nothing Nothing (Just "anthropic") Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["opencode", "run", "hello"], Map.singleton "CCC_PROVIDER" "anthropic", [])

    it "returns Left for empty prompt" $ do
      let parsed = ParsedArgs Nothing Nothing Nothing Nothing Nothing ""
          result = resolveCommand parsed Nothing
      result `shouldBe` Left "prompt must not be empty"

    it "returns Left for whitespace-only prompt" $ do
      let parsed = ParsedArgs Nothing Nothing Nothing Nothing Nothing "   "
          result = resolveCommand parsed Nothing
      result `shouldBe` Left "prompt must not be empty"

    it "resolves alias from config" $ do
      let aliasDef = AliasDef (Just "claude") (Just 2) Nothing Nothing Nothing
          config = defaultConfig { ccAliases = Map.singleton "fast" aliasDef }
          parsed = ParsedArgs Nothing Nothing Nothing Nothing (Just "fast") "go"
          result = resolveCommand parsed (Just config)
      result `shouldBe` Right (["claude", "--thinking", "enabled", "--effort", "medium", "go"], Map.empty, [])

    it "explicit runner overrides alias runner but alias thinking still applies" $ do
      let aliasDef = AliasDef (Just "claude") (Just 2) Nothing Nothing Nothing
          config = defaultConfig { ccAliases = Map.singleton "fast" aliasDef }
          parsed = ParsedArgs (Just "kimi") Nothing Nothing Nothing (Just "fast") "go"
          result = resolveCommand parsed (Just config)
      result `shouldBe` Right (["kimi", "--thinking", "go"], Map.empty, [])

    it "uses name fallback as agent when preset is missing" $ do
      let parsed = ParsedArgs Nothing Nothing Nothing Nothing (Just "reviewer") "go"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["opencode", "run", "--agent", "reviewer", "go"], Map.empty, [])

    it "uses preset agent before name fallback" $ do
      let aliasDef = AliasDef Nothing Nothing Nothing Nothing (Just "specialist")
          config = defaultConfig { ccAliases = Map.singleton "review" aliasDef }
          parsed = ParsedArgs Nothing Nothing Nothing Nothing (Just "review") "go"
          result = resolveCommand parsed (Just config)
      result `shouldBe` Right (["opencode", "run", "--agent", "specialist", "go"], Map.empty, [])

    it "warns when agent is unsupported" $ do
      let parsed = ParsedArgs (Just "rc") Nothing Nothing Nothing (Just "reviewer") "go"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["roocode", "go"], Map.empty, ["warning: runner \"roocode\" does not support agents; ignoring @reviewer"])

    it "uses config default thinking when not set" $ do
      let config = defaultConfig { ccDefaultThinking = Just 1 }
          parsed = ParsedArgs Nothing Nothing Nothing Nothing Nothing "go"
          result = resolveCommand parsed (Just config)
      result `shouldBe` Right (["opencode", "run", "go"], Map.empty, [])

    it "uses config default thinking with claude runner" $ do
      let config = defaultConfig { ccDefaultThinking = Just 1 }
          parsed = ParsedArgs (Just "claude") Nothing Nothing Nothing Nothing "go"
          result = resolveCommand parsed (Just config)
      result `shouldBe` Right (["claude", "--thinking", "enabled", "--effort", "low", "go"], Map.empty, [])

    it "uses config default model and provider" $ do
      let config = defaultConfig { ccDefaultModel = "claude-3", ccDefaultProvider = "anthropic" }
          parsed = ParsedArgs (Just "claude") Nothing Nothing Nothing Nothing "go"
          result = resolveCommand parsed (Just config)
      result `shouldBe` Right (["claude", "--model", "claude-3", "go"], Map.singleton "CCC_PROVIDER" "anthropic", [])

    it "handles kimi runner with thinking 0" $ do
      let parsed = ParsedArgs (Just "kimi") (Just 0) Nothing Nothing Nothing "hello"
          result = resolveCommand parsed Nothing
      result `shouldBe` Right (["kimi", "--no-thinking", "hello"], Map.empty, [])
