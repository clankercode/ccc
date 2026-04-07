module Main where

import CallCodingClis.PromptSpec (buildPromptSpec)
import CallCodingClis.Runner (run)
import CallCodingClis.Types
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
      hPutStrLn stderr "usage: ccc \"<Prompt>\""
      exitWith (ExitFailure 1)
