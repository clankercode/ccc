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
import System.IO (hClose, hGetContents, hPutStr, hSetEncoding, utf8)
import System.IO.Error (tryIOError)
import System.Process (CreateProcess(..), StdStream(..), createProcess, proc, waitForProcess)

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
            , std_in  = CreatePipe
            , std_out = CreatePipe
            , std_err = CreatePipe
            }
      result <- tryIOError $ do
        (Just hIn, Just hOut, Just hErr, ph) <- createProcess procSpec
        hSetEncoding hIn utf8
        hSetEncoding hOut utf8
        hSetEncoding hErr utf8
        hPutStr hIn (fromMaybe "" (csStdinText spec))
        hClose hIn
        out <- hGetContents hOut
        errStr <- hGetContents hErr
        ec <- waitForProcess ph
        return (ec, out, errStr)
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
