module CallCodingClis.PromptSpec where

import Prelude
import Data.String (trim)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Foreign.Object as Object
import CallCodingClis.Types (CommandSpec)

buildPromptSpec :: String -> Either String CommandSpec
buildPromptSpec prompt =
  let trimmed = trim prompt
  in if trimmed == ""
     then Left "prompt must not be empty"
     else Right
       { argv: ["opencode", "run", trimmed]
       , stdinText: Nothing
       , cwd: Nothing
       , env: Object.empty
       }
