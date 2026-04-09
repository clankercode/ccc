module CallCodingClis.Config
  ( AliasDef
  , CccConfig
  , defaultConfig
  , parseConfig
  , loadConfig
  ) where

import Prelude

import Data.Array (uncons)
import Data.Foldable (foldl)
import Data.Int (fromString)
import Data.Maybe (Maybe(..))
import Data.String (trim, null, drop, indexOf, split, replaceAll)
import Data.String.CodeUnits as CU
import Data.String.Pattern (Pattern(..), Replacement(..))
import Effect (Effect)
import Foreign.Object as Object
import Node.Process (lookupEnv)

type AliasDef =
  { runner :: Maybe String
  , thinking :: Maybe Int
  , provider :: Maybe String
  , model :: Maybe String
  , agent :: Maybe String
  }

type CccConfig =
  { defaultRunner :: String
  , defaultProvider :: String
  , defaultModel :: String
  , defaultThinking :: Maybe Int
  , aliases :: Object.Object AliasDef
  , abbreviations :: Object.Object String
  }

type ParseState =
  { config :: CccConfig
  , section :: Maybe String
  , aliasName :: Maybe String
  , aliasDef :: AliasDef
  }

emptyAlias :: AliasDef
emptyAlias =
  { runner: Nothing
  , thinking: Nothing
  , provider: Nothing
  , model: Nothing
  , agent: Nothing
  }

defaultConfig :: CccConfig
defaultConfig =
  { defaultRunner: "oc"
  , defaultProvider: ""
  , defaultModel: ""
  , defaultThinking: Nothing
  , aliases: Object.empty
  , abbreviations: Object.empty
  }

foreign import readConfigImpl :: String -> Effect String

foreign import xdgConfigHome :: Effect String

configPaths :: Effect (Array String)
configPaths = do
  xdg <- xdgConfigHome
  home <- lookupEnv "HOME"
  let xdgPath = if null xdg then [] else [xdg <> "/ccc/config.toml"]
      homePath = case home of
        Nothing -> []
        Just h -> [h <> "/.config/ccc/config.toml"]
  pure (xdgPath <> homePath)

loadConfig :: Effect CccConfig
loadConfig = do
  paths <- configPaths
  loadConfigFromPaths paths

loadConfigFromPaths :: Array String -> Effect CccConfig
loadConfigFromPaths arr = case uncons arr of
  Nothing -> pure defaultConfig
  Just { head: path, tail: rest } -> do
    contents <- readConfigImpl path
    if null contents then loadConfigFromPaths rest
    else pure (parseConfig contents)

parseConfig :: String -> CccConfig
parseConfig contents = finalize $ foldl step initial (split (Pattern "\n") contents)
  where
  initial :: ParseState
  initial =
    { config: defaultConfig
    , section: Nothing
    , aliasName: Nothing
    , aliasDef: emptyAlias
    }

  finalize :: ParseState -> CccConfig
  finalize state =
    flushAlias state.config state.aliasName state.aliasDef

  step :: ParseState -> String -> ParseState
  step state line =
    let trimmed = trim line
    in if trimmed == "" || CU.take 1 trimmed == "#"
       then state
       else if CU.take 1 trimmed == "[" then
         let flushedConfig = flushAlias state.config state.aliasName state.aliasDef
         in case parseSection trimmed of
              Just { kind: "defaults", aliasName: Nothing } ->
                state { config = flushedConfig, section = Just "defaults", aliasName = Nothing, aliasDef = emptyAlias }
              Just { kind: "abbreviations", aliasName: Nothing } ->
                state { config = flushedConfig, section = Just "abbreviations", aliasName = Nothing, aliasDef = emptyAlias }
              Just { kind: "alias", aliasName: Just aliasName } ->
                state { config = flushedConfig, section = Just "alias", aliasName = Just aliasName, aliasDef = emptyAlias }
              _ ->
                state { config = flushedConfig, section = Nothing, aliasName = Nothing, aliasDef = emptyAlias }
       else case parseKeyValue trimmed of
         Nothing -> state
         Just { key, value } ->
           case state.section of
             Just "defaults" -> state { config = applyDefaultSetting state.config key value }
             Just "abbreviations" -> state { config = state.config { abbreviations = Object.insert key value state.config.abbreviations } }
             Just "alias" -> state { aliasDef = applyAliasSetting state.aliasDef key value }
             Nothing -> state { config = applyDefaultSetting state.config key value }
             _ -> state

  parseSection :: String -> Maybe { kind :: String, aliasName :: Maybe String }
  parseSection header =
    let inner = CU.take (CU.length header - 2) (CU.drop 1 header)
    in case split (Pattern ".") inner of
         ["defaults"] -> Just { kind: "defaults", aliasName: Nothing }
         ["abbreviations"] -> Just { kind: "abbreviations", aliasName: Nothing }
         ["aliases", aliasName] -> Just { kind: "alias", aliasName: Just aliasName }
         ["alias", aliasName] -> Just { kind: "alias", aliasName: Just aliasName }
         _ -> Nothing

  parseKeyValue :: String -> Maybe { key :: String, value :: String }
  parseKeyValue line = case indexOf (Pattern "=") line of
    Nothing -> Nothing
    Just i ->
      let key = trim (CU.take i line)
          value = trim (drop (i + 1) line)
      in if key == "" then Nothing else Just { key, value: trimQuotes value }

  flushAlias :: CccConfig -> Maybe String -> AliasDef -> CccConfig
  flushAlias cfg aliasName aliasDef =
    case aliasName of
      Nothing -> cfg
      Just name -> cfg { aliases = Object.insert name aliasDef cfg.aliases }

  applyDefaultSetting :: CccConfig -> String -> String -> CccConfig
  applyDefaultSetting cfg key value = case key of
    "runner" -> cfg { defaultRunner = value }
    "default_runner" -> cfg { defaultRunner = value }
    "provider" -> cfg { defaultProvider = value }
    "model" -> cfg { defaultModel = value }
    "thinking" ->
      case fromString value of
        Just n -> cfg { defaultThinking = Just n }
        Nothing -> cfg
    _ -> cfg

  applyAliasSetting :: AliasDef -> String -> String -> AliasDef
  applyAliasSetting aliasDef key value = case key of
    "runner" -> aliasDef { runner = nonEmpty value }
    "thinking" ->
      case fromString value of
        Just n -> aliasDef { thinking = Just n }
        Nothing -> aliasDef
    "provider" -> aliasDef { provider = nonEmpty value }
    "model" -> aliasDef { model = nonEmpty value }
    "agent" -> aliasDef { agent = nonEmpty value }
    _ -> aliasDef

  nonEmpty :: String -> Maybe String
  nonEmpty value = if value == "" then Nothing else Just value

  trimQuotes :: String -> String
  trimQuotes s =
    let t = trim s
    in if CU.length t >= 2 && CU.take 1 t == "\"" && CU.take 1 (CU.drop (CU.length t - 1) t) == "\""
       then replaceAll (Pattern "\"") (Replacement "") t
       else t
