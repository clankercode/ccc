module CallCodingClis.Config
  ( loadConfig
  , parseConfig
  ) where

import CallCodingClis.Parser (AliasDef(..), CccConfig(..), defaultConfig)
import Data.Char (isSpace)
import Data.List (isPrefixOf)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import System.Directory (getHomeDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Error (tryIOError)

configFileName :: FilePath
configFileName = "config.toml"

configDirName :: FilePath
configDirName = "ccc"

defaultConfigPaths :: IO [FilePath]
defaultConfigPaths = do
  xdg <- lookupEnv "XDG_CONFIG_HOME"
  home <- getHomeDirectory
  let xdgPath = case xdg of
        Just d  -> [d </> configDirName </> configFileName]
        Nothing -> []
      homePath = [home </> ".config" </> configDirName </> configFileName]
  return (xdgPath ++ homePath)

loadConfig :: Maybe FilePath -> IO CccConfig
loadConfig (Just path) = do
  result <- tryIOError (readFile path)
  case result of
    Left _  -> return defaultConfig
    Right contents ->
      case parseConfig contents of
        Left _    -> return defaultConfig
        Right cfg -> return cfg
loadConfig Nothing = do
  paths <- defaultConfigPaths
  loadFirst paths
  where
    loadFirst [] = return defaultConfig
    loadFirst (p:ps) = do
      result <- tryIOError (readFile p)
      case result of
        Left _ -> loadFirst ps
        Right contents ->
          case parseConfig contents of
            Left _    -> loadFirst ps
            Right cfg -> return cfg

parseConfig :: String -> Either String CccConfig
parseConfig contents = Right finalCfg
  where
    stripLine :: String -> String
    stripLine = reverse . dropWhile isSpace . reverse . dropWhile isSpace

    (finalCfg, _) = foldl processLine (defaultConfig, Nothing :: Maybe (String, String)) (lines contents)

    processLine (cfg, section) line =
      let trimmed = stripLine line
      in case trimmed of
        ""      -> (cfg, section)
        '#':_   -> (cfg, section)
        '[':rest ->
          case break (== ']') rest of
            (secName, "]")
              | "alias." `isPrefixOf` secName ->
                  (cfg, Just ("alias", drop 6 secName))
              | secName == "abbreviations" ->
                  (cfg, Just ("abbreviations", ""))
              | otherwise -> (cfg, Nothing)
            _ -> (cfg, Nothing)
        _ ->
          case break (== '=') trimmed of
            (keyRaw, '=':valRaw) ->
              let key = stripLine keyRaw
                  val = stripLine valRaw
              in applySetting cfg section key val
            _ -> (cfg, section)

    applySetting cfg Nothing key val = case key of
      "default_runner"   -> (cfg { ccDefaultRunner = val }, Nothing)
      "default_provider" -> (cfg { ccDefaultProvider = val }, Nothing)
      "default_model"    -> (cfg { ccDefaultModel = val }, Nothing)
      "default_thinking" -> (cfg { ccDefaultThinking = readMaybeInt val }, Nothing)
      _                  -> (cfg, Nothing)

    applySetting cfg (Just ("alias", name)) key val =
      let aliases = ccAliases cfg
          existing = Map.findWithDefault (AliasDef Nothing Nothing Nothing Nothing) name aliases
          updated = case key of
            "runner"   -> existing { adRunner = nonEmpty val }
            "thinking" -> existing { adThinking = readMaybeInt val }
            "provider" -> existing { adProvider = nonEmpty val }
            "model"    -> existing { adModel = nonEmpty val }
            _          -> existing
      in (cfg { ccAliases = Map.insert name updated aliases }, Just ("alias", name))

    applySetting cfg (Just ("abbreviations", _)) key val
      | not (null key) && not (null val) =
          (cfg { ccAbbreviations = Map.insert key val (ccAbbreviations cfg) }, Just ("abbreviations", ""))
    applySetting cfg section _ _ = (cfg, section)

    readMaybeInt s = case reads s of
      [(n, "")] -> Just n
      _         -> Nothing

    nonEmpty "" = Nothing
    nonEmpty s  = Just s
