module CallCodingClis.Runner where

import Prelude
import Effect (Effect)
import Data.Maybe (Maybe(..))
import Data.Nullable (Nullable, toNullable)
import Foreign.Object (Object, isEmpty)
import CallCodingClis.Types (CommandSpec, CompletedRun)

type ForeignSpec =
  { argv :: Array String
  , stdinText :: Nullable String
  , cwd :: Nullable String
  , env :: Nullable (Object String)
  }

foreign import runSyncImpl :: ForeignSpec -> Effect CompletedRun

toForeign :: CommandSpec -> ForeignSpec
toForeign spec =
  { argv: spec.argv
  , stdinText: toNullable spec.stdinText
  , cwd: toNullable spec.cwd
  , env: toNullable (if isEmpty spec.env then Nothing else Just spec.env)
  }

run :: CommandSpec -> Effect CompletedRun
run spec = runSyncImpl (toForeign spec)

stream :: CommandSpec -> (String -> String -> Effect Unit) -> Effect CompletedRun
stream spec callback = do
  result <- run spec
  when (result.stdout /= "") $ callback "stdout" result.stdout
  when (result.stderr /= "") $ callback "stderr" result.stderr
  pure result
