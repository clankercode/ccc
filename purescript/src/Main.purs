module Main where

import Prelude
import Effect (Effect)
import Effect.Console (error)
import Data.Array (drop)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Node.Process (argv, lookupEnv)
import CallCodingClis.Config (loadConfig)
import CallCodingClis.Parser (parseArgs, resolveCommand)
import CallCodingClis.Runner (run)
import CallCodingClis.Help (helpText, runnerChecklist)

foreign import writeStdout :: String -> Effect Unit
foreign import writeStderr :: String -> Effect Unit
foreign import processExit :: Int -> Effect Unit

main :: Effect Unit
main = do
  rawArgs <- argv
  let args = drop 2 rawArgs
  case args of
    [] -> do
      writeStderr $ "usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\"\n"
      checklist <- runnerChecklist
      writeStderr $ checklist <> "\n"
      processExit 1
    ["--help"] -> do
      checklist <- runnerChecklist
      writeStdout $ helpText <> "\n" <> checklist <> "\n"
      processExit 0
    ["-h"] -> do
      checklist <- runnerChecklist
      writeStdout $ helpText <> "\n" <> checklist <> "\n"
      processExit 0
    _ -> do
      let parsed = parseArgs args
      if parsed.prompt == "" then do
        writeStderr "prompt must not be empty\n"
        processExit 1
      else do
        config <- loadConfig
        let spec = resolveCommand parsed config
        runnerBin <- lookupEnv "CCC_REAL_OPENCODE"
        let adjustedSpec = case runnerBin of
              Nothing -> spec
              Just bin -> spec { argv = [bin] <> drop 1 spec.argv }
        result <- run adjustedSpec
        when (result.stdout /= "") $ writeStdout result.stdout
        when (result.stderr /= "") $ writeStderr result.stderr
        processExit result.exitCode
