module Main where

import CallCodingClis.Config (loadConfig)
import CallCodingClis.Help (printHelp, printUsage)
import CallCodingClis.Parser (parseArgs, resolveCommand)
import CallCodingClis.Runner (run)
import CallCodingClis.Types
import Data.Map.Strict (toList)
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode(..), exitWith)
import System.IO (hPutStr, hPutStrLn, hSetEncoding, stderr, stdout, utf8)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  args <- getArgs
  case args of
    [] -> do
      printUsage
      exitWith (ExitFailure 1)
    ["--help"] -> do
      printHelp
      exitWith ExitSuccess
    ["-h"] -> do
      printHelp
      exitWith ExitSuccess
    _ -> do
      config <- loadConfig Nothing
      let parsed = parseArgs args
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
