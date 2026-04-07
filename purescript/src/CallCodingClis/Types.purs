module CallCodingClis.Types where

import Data.Maybe (Maybe)
import Foreign.Object (Object)

type CommandSpec =
  { argv :: Array String
  , stdinText :: Maybe String
  , cwd :: Maybe String
  , env :: Object String
  }

type CompletedRun =
  { argv :: Array String
  , exitCode :: Int
  , stdout :: String
  , stderr :: String
  }
