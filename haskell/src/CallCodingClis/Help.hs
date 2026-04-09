module CallCodingClis.Help
  ( helpText
  , usageText
  , printHelp
  , printUsage
  ) where

import CallCodingClis.Parser (RunnerInfo(..), runnerRegistry)
import Control.Exception (SomeException, try)
import Data.Char (isSpace)
import Data.List (dropWhileEnd)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import System.Directory (findExecutable)
import System.Exit (ExitCode(..))
import System.IO (hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)

helpText :: String
helpText = unlines
  [ "ccc \x2014 call coding CLIs"
  , ""
  , "Usage:"
  , "  ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""
  , "  ccc --help"
  , "  ccc -h"
  , ""
  , "Slots (in order):"
  , "  runner        Select which coding CLI to use (default: oc)"
  , "                opencode (oc), claude (cc), kimi (k), codex (c/cx), roocode (rc), crush (cr)"
  , "  +thinking     Set thinking level: +0 (off) through +4 (max)"
  , "  :provider:model  Override provider and model"
  , "  @name         Use a named preset from config; if no preset exists, treat it as an agent"
  , ""
  , "Examples:"
  , "  ccc \"Fix the failing tests\""
  , "  ccc oc \"Refactor auth module\""
  , "  ccc cc +2 :anthropic:claude-sonnet-4-20250514 \"Add tests\""
  , "  ccc k +4 \"Debug the parser\""
  , "  ccc @reviewer \"Audit the API boundary\""
  , "  ccc c \"Write a unit test\""
  , "  ccc rc \"Probe RooCode\""
  , ""
  , "Config:"
  , "  ~/.config/ccc/config.toml  \x2014 default runner, presets, abbreviations"
  ]

usageText :: String
usageText = "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\""

canonicalRunners :: [(String, String)]
canonicalRunners =
  [ ("opencode", "oc")
  , ("claude", "cc")
  , ("kimi", "k")
  , ("codex", "c/cx")
  , ("roocode", "rc")
  , ("crush", "cr")
  ]

getBinary :: String -> String
getBinary name = case Map.lookup name runnerRegistry of
  Just info -> riBinary info
  Nothing   -> name

getVersion :: String -> IO String
getVersion binary = do
  mResult <- timeout (3000000) $ do
    r <- try (readProcessWithExitCode binary ["--version"] "")
      :: IO (Either SomeException (ExitCode, String, String))
    case r of
      Left _ -> return ""
      Right (ExitSuccess, out, _) ->
        case lines (strip out) of
          [] -> return ""
          (firstLine:_) -> return firstLine
      Right _ -> return ""
  case mResult of
    Nothing -> return ""
    Just v  -> return v

strip :: String -> String
strip = dropWhileEnd isSpace . dropWhile isSpace

padRight :: Int -> String -> String
padRight n s = s ++ replicate (max 0 (n - length s)) ' '

runnerChecklist :: IO String
runnerChecklist = do
  entries <- mapM checkRunner canonicalRunners
  return $ "Runners:" ++ concatMap ("\n" ++) entries

checkRunner :: (String, String) -> IO String
checkRunner (name, _alias) = do
  let binary = getBinary name
  mPath <- findExecutable binary
  case mPath of
    Nothing -> return $
      "  [-] " ++ padRight 10 name ++ "(" ++ binary ++ ")  not found"
    Just _ -> do
      version <- getVersion binary
      let tag = if null version then "found" else version
      return $
        "  [+] " ++ padRight 10 name ++ "(" ++ binary ++ ")  " ++ tag

printHelp :: IO ()
printHelp = do
  checklist <- runnerChecklist
  putStrLn (helpText ++ "\n" ++ checklist)

printUsage :: IO ()
printUsage = do
  hPutStrLn stderr usageText
  checklist <- runnerChecklist
  hPutStrLn stderr checklist
