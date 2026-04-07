module Main where

import Prelude
import Effect (Effect)
import Effect.Console (error)
import Data.Array (drop)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Node.Process (argv, lookupEnv)
import CallCodingClis.PromptSpec (buildPromptSpec)
import CallCodingClis.Runner (run)

foreign import writeStdout :: String -> Effect Unit
foreign import writeStderr :: String -> Effect Unit
foreign import processExit :: Int -> Effect Unit

main :: Effect Unit
main = do
  rawArgs <- argv
  let args = drop 2 rawArgs
  case args of
    [prompt] ->
      case buildPromptSpec prompt of
        Left err -> do
          error err
          processExit 1
        Right spec -> do
          runnerBin <- lookupEnv "CCC_REAL_OPENCODE"
          let adjustedSpec = case runnerBin of
                Nothing -> spec
                Just bin -> spec { argv = [bin] <> drop 1 spec.argv }
          result <- run adjustedSpec
          when (result.stdout /= "") $ writeStdout result.stdout
          when (result.stderr /= "") $ writeStderr result.stderr
          processExit result.exitCode
    _ -> do
      error "usage: ccc \"<Prompt>\""
      processExit 1
