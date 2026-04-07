module CallCodingClis.PromptSpec
  ( buildPromptSpec
  ) where

import CallCodingClis.Types
import Data.Char (isSpace)
import Data.List (dropWhileEnd)

strip :: String -> String
strip = dropWhileEnd isSpace . dropWhile isSpace

buildPromptSpec :: String -> Either String CommandSpec
buildPromptSpec prompt =
  let trimmed = strip prompt
  in if null trimmed
     then Left "prompt must not be empty"
     else Right $ CommandSpec ["opencode", "run", trimmed] Nothing Nothing []
