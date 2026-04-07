module Main where

import CallCodingClis.Config (loadConfig)
import CallCodingClis.Parser (parseArgs, resolveCommand)
import CallCodingClis.PromptSpec (buildPromptSpec)
import CallCodingClis.Runner (run)
import CallCodingClis.Types
import Data.List (intercalate)
import Data.Map.Strict (toList)
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode(..), exitWith)
import System.IO (hPutStr, hPutStrLn, stderr)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [prompt] -> case buildPromptSpec prompt of
      Left err -> do
        hPutStrLn stderr err
        exitWith (ExitFailure 1)
      Right spec -> do
        mOverride <- lookupEnv "CCC_REAL_OPENCODE"
        let spec' = case mOverride of
              Nothing  -> spec
              Just bin -> spec { csArgv = bin : tail (csArgv spec) }
        result <- run spec'
        putStr (crStdout result)
        hPutStr stderr (crStderr result)
        exitWith (case crExitCode result of
                    0 -> ExitSuccess
                    n -> ExitFailure n)
    _ -> do
      let parsed = parseArgs args
      config <- loadConfig Nothing
      case resolveCommand parsed (Just config) of
        Left err -> do
          hPutStrLn stderr err
          exitWith (ExitFailure 1)
        Right (argv, envOverrides) -> do
          mOverride <- lookupEnv "CCC_REAL_OPENCODE"
          let argv' = case mOverride of
                Nothing  -> argv
                Just bin -> bin : tail argv
              spec = CommandSpec argv' Nothing Nothing (toList envOverrides)
          result <- run spec
          putStr (crStdout result)
          hPutStr stderr (crStderr result)
          exitWith (case crExitCode result of
                      0 -> ExitSuccess
                      n -> ExitFailure n)
