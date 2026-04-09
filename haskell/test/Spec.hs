module Main where

import CallCodingClis.Config (parseConfig)
import CallCodingClis.PromptSpec (buildPromptSpec)
import CallCodingClis.Runner (run, stream)
import CallCodingClis.Help (helpText, usageText)
import CallCodingClis.Parser (AliasDef(..), ccAliases, ccDefaultRunner)
import CallCodingClis.Types
import Control.Monad (when)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import ParserSpec (parserSpec)
import JsonOutputSpec (jsonOutputSpec)
import System.Exit (exitFailure, exitSuccess)
import Test.Hspec (hspec)

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  when (expected /= actual) $ do
    putStrLn $ "FAIL: " ++ label
    putStrLn $ "  expected: " ++ show expected
    putStrLn $ "  actual:   " ++ show actual
    exitFailure

assertContains :: String -> String -> String -> IO ()
assertContains label needle haystack =
  when (not (needle `isInfixOf` haystack)) $ do
    putStrLn $ "FAIL: " ++ label
    putStrLn $ "  expected to contain: " ++ show needle
    putStrLn $ "  actual: " ++ show haystack
    exitFailure

main :: IO ()
main = do
  hspec $ do
    parserSpec
    jsonOutputSpec

  putStrLn "=== buildPromptSpec ==="

  case buildPromptSpec "hello" of
    Right spec -> do
      assertEqual "valid argv" ["opencode", "run", "hello"] (csArgv spec)
      assertEqual "valid stdinText" Nothing (csStdinText spec)
      assertEqual "valid cwd" Nothing (csCwd spec)
      assertEqual "valid env" [] (csEnv spec)
    Left err -> do
      putStrLn $ "FAIL: valid prompt returned Left: " ++ err
      exitFailure

  case buildPromptSpec "" of
    Left err -> assertContains "empty prompt error" "empty" err
    Right _  -> do
      putStrLn "FAIL: empty prompt should return Left"
      exitFailure

  case buildPromptSpec "   " of
    Left err -> assertContains "whitespace prompt error" "empty" err
    Right _  -> do
      putStrLn "FAIL: whitespace-only prompt should return Left"
      exitFailure

  case buildPromptSpec "  foo  " of
    Right spec -> assertEqual "trimmed argv" ["opencode", "run", "foo"] (csArgv spec)
    Left err   -> do
      putStrLn $ "FAIL: trimmable prompt returned Left: " ++ err
      exitFailure

  case buildPromptSpec "\t \n bar \n \t" of
    Right spec -> assertEqual "mixed whitespace argv" ["opencode", "run", "bar"] (csArgv spec)
    Left err   -> do
      putStrLn $ "FAIL: mixed whitespace prompt returned Left: " ++ err
      exitFailure

  putStrLn "=== Config ==="

  case parseConfig "[defaults]\nrunner = \"claude\"\n" of
    Right cfg -> assertEqual "defaults section runner" "claude" (ccDefaultRunner cfg)
    Left err -> do
      putStrLn $ "FAIL: parseConfig defaults section returned Left: " ++ err
      exitFailure

  case parseConfig "[aliases.work]\nrunner = \"cc\"\nagent = \"reviewer\"\n" of
    Right cfg -> do
      case Map.lookup "work" (ccAliases cfg) of
        Just aliasDef -> assertEqual "alias agent" (Just "reviewer") (adAgent aliasDef)
        Nothing -> do
          putStrLn "FAIL: parseConfig aliases section missing work alias"
          exitFailure
    Left err -> do
      putStrLn $ "FAIL: parseConfig aliases section returned Left: " ++ err
      exitFailure

  putStrLn "=== Help ==="

  assertContains "help usage" "ccc [controls...] \"<Prompt>\"" helpText
  assertContains "help example 1" "ccc cc +2 :anthropic:claude-sonnet-4-20250514 @reviewer \"Add tests\"" helpText
  assertContains "help example 2" "ccc c +4 :openai:gpt-5.4-mini @agent \"Debug the parser\"" helpText
  assertContains "help runner remap" "opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)" helpText
  assertContains "help agent fallback" "if no preset exists, treat it as an agent" helpText
  assertContains "usage line" "[@name]" usageText

  putStrLn "=== Runner ==="

  let badSpec = CommandSpec ["/nonexistent_binary_xyz"] Nothing Nothing []
  badResult <- run badSpec
  assertEqual "bad binary exit code" 1 (crExitCode badResult)
  assertContains "bad binary stderr" "failed to start /nonexistent_binary_xyz" (crStderr badResult)

  let echoSpec = CommandSpec ["echo", "runner_test"] Nothing Nothing []
  echoResult <- run echoSpec
  assertEqual "echo exit code" 0 (crExitCode echoResult)
  assertContains "echo stdout" "runner_test" (crStdout echoResult)

  let failSpec = CommandSpec ["sh", "-c", "exit 42"] Nothing Nothing []
  failResult <- run failSpec
  assertEqual "nonzero exit code" 42 (crExitCode failResult)

  putStrLn "=== stream ==="

  let streamSpec = CommandSpec ["echo", "streamtest"] Nothing Nothing []
  ref <- newIORef ""
  streamResult <- stream streamSpec $ \chan chunk -> do
    modifyIORef' ref (\acc -> acc ++ chan ++ ":" ++ chunk)
  streamOutput <- readIORef ref
  assertContains "stream callback" "stdout:" streamOutput
  assertEqual "stream exit code" 0 (crExitCode streamResult)

  putStrLn "All tests passed."
  exitSuccess
