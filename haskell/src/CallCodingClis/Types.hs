module CallCodingClis.Types where

data CommandSpec = CommandSpec
  { csArgv      :: [String]
  , csStdinText :: Maybe String
  , csCwd       :: Maybe FilePath
  , csEnv       :: [(String, String)]
  } deriving (Eq, Show)

data CompletedRun = CompletedRun
  { crArgv     :: [String]
  , crExitCode :: Int
  , crStdout   :: String
  , crStderr   :: String
  } deriving (Eq, Show)
