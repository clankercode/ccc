module CallCodingClis.Config where

import Prelude
import Effect (Effect)
import Data.Maybe (Maybe(..))
import Data.String (trim, null, contains, drop, indexOf, split, length, replaceAll)
import Data.String.Pattern (Pattern(..), Replacement(..))
import Node.Process (lookupEnv)

type CccConfig =
  { defaultRunner :: String
  }

defaultConfig :: CccConfig
defaultConfig = { defaultRunner: "oc" }

foreign import readConfigImpl :: String -> Effect String

foreign import xdgConfigHome :: Effect String

configPaths :: Effect (Array String)
configPaths = do
  xdg <- xdgConfigHome
  home <- lookupEnv "HOME"
  let xdgPath = if null xdg then [] else [xdg <> "/ccc/config.toml"]
  let homePath = case home of
        Nothing -> []
        Just h -> [h <> "/.config/ccc/config.toml"]
  pure (xdgPath <> homePath)

loadConfig :: Effect CccConfig
loadConfig = do
  paths <- configPaths
  loadConfigFromPaths paths

loadConfigFromPaths :: Array String -> Effect CccConfig
loadConfigFromPaths [] = pure defaultConfig
loadConfigFromPaths (path:rest) = do
  contents <- readConfigImpl path
  if null contents then loadConfigFromPaths rest
  else pure (parseConfig contents)

parseRunnerAlias :: String -> String
parseRunnerAlias "cc" = "claude"
parseRunnerAlias "oc" = "opencode"
parseRunnerAlias "c" = "claude"
parseRunnerAlias "k" = "kimi"
parseRunnerAlias other = other

parseConfig :: String -> CccConfig
parseConfig contents =
  let
    lines = split (Pattern "\n") contents
    defaultsRunner = extractDefaultsRunner lines
  in case defaultsRunner of
    Nothing -> defaultConfig
    Just runner -> defaultConfig { defaultRunner = parseRunnerAlias (trim runner) }

extractDefaultsRunner :: Array String -> Maybe String
extractDefaultsRunner [] = Nothing
extractDefaultsRunner (line:rest) =
  let trimmed = trim line
  in if contains (Pattern "runner") trimmed && contains (Pattern "=") trimmed
     then extractValue trimmed
     else extractDefaultsRunner rest

extractValue :: String -> Maybe String
extractValue s = case indexOf (Pattern "=") s of
  Nothing -> Nothing
  Just i -> Just (trim (trimQuotes (drop (i + 1) s)))

trimQuotes :: String -> String
trimQuotes s =
  let t = trim s
  in if length t >= 2 && contains (Pattern "\"") t
     then replaceAll (Pattern "\"") (Replacement "") t
     else t
