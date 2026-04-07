module CallCodingClis.Runner
  ( run
  , stream
  ) where

import CallCodingClis.Types
import Control.Exception (displayException)
import Control.Monad (when)
import Data.Maybe (fromMaybe)
import System.Environment (getEnvironment)
import System.Exit (ExitCode(..))
import System.IO.Error (tryIOError)
import System.Process (CreateProcess(..), proc, readCreateProcessWithExitCode)

run :: CommandSpec -> IO CompletedRun
run spec
  | null (csArgv spec) = return $ CompletedRun [] 1 ""
      "failed to start (unknown): argv is empty\n"
  | otherwise = do
      let (cmd:args) = csArgv spec
      envOverride <- envWithOverrides (csEnv spec)
      let procSpec = (proc cmd args)
            { cwd = csCwd spec
            , env = envOverride
            }
          stdinInput = fromMaybe "" (csStdinText spec)
      result <- tryIOError $ readCreateProcessWithExitCode procSpec stdinInput
      case result of
        Left err -> return $ CompletedRun (csArgv spec) 1 ""
          ("failed to start " ++ cmd ++ ": " ++ displayException err ++ "\n")
        Right (ec, out, errStr) -> return $ CompletedRun (csArgv spec) (toExitInt ec) out errStr

stream :: CommandSpec -> (String -> String -> IO ()) -> IO CompletedRun
stream spec callback = do
  result <- run spec
  when (not (null (crStdout result))) $ callback "stdout" (crStdout result)
  when (not (null (crStderr result))) $ callback "stderr" (crStderr result)
  return result

toExitInt :: ExitCode -> Int
toExitInt ExitSuccess     = 0
toExitInt (ExitFailure n) = n

envWithOverrides :: [(String, String)] -> IO (Maybe [(String, String)])
envWithOverrides []       = return Nothing
envWithOverrides overrides = do
  currentEnv <- getEnvironment
  return $ Just (currentEnv ++ overrides)
