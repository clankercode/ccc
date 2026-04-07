module Test.Main where

import Prelude
import Effect (Effect)
import Effect.Console (log)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import CallCodingClis.PromptSpec (buildPromptSpec)

check :: String -> Boolean -> Effect Unit
check name true = log $ "PASS: " <> name
check name false = log $ "FAIL: " <> name

main :: Effect Unit
main = do
  let r1 = case buildPromptSpec "Fix the failing tests" of
        Right spec -> spec.argv == ["opencode", "run", "Fix the failing tests"]
        Left _ -> false
  check "buildPromptSpec: valid prompt" r1

  let r2 = case buildPromptSpec "" of
        Left msg -> msg == "prompt must not be empty"
        Right _ -> false
  check "buildPromptSpec: empty prompt rejected" r2

  let r3 = case buildPromptSpec "   " of
        Left _ -> true
        Right _ -> false
  check "buildPromptSpec: whitespace prompt rejected" r3

  let r4 = case buildPromptSpec "  hello  " of
        Right spec -> spec.argv == ["opencode", "run", "hello"]
        Left _ -> false
  check "buildPromptSpec: prompt trimmed" r4

  let r5 = case buildPromptSpec "\t\nmixed whitespace \n" of
        Right spec -> spec.argv == ["opencode", "run", "mixed whitespace"]
        Left _ -> false
  check "buildPromptSpec: tabs and newlines trimmed" r5

  let r6 = case buildPromptSpec "Fix the failing tests" of
        Right spec -> spec.stdinText == Nothing
        Left _ -> false
  check "buildPromptSpec: stdinText is Nothing" r6

  let r7 = case buildPromptSpec "Fix the failing tests" of
        Right spec -> spec.cwd == Nothing
        Left _ -> false
  check "buildPromptSpec: cwd is Nothing" r7

  log "done"
