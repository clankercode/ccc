module CallCodingClis.Parser
  ( RunnerInfo(..)
  , ParsedArgs(..)
  , AliasDef(..)
  , CccConfig(..)
  , runnerRegistry
  , defaultConfig
  , parseArgs
  , resolveCommand
  ) where

import Control.Applicative ((<|>))
import Data.Char (isSpace, toLower)
import Data.List (dropWhileEnd)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)

data RunnerInfo = RunnerInfo
  { riBinary        :: String
  , riExtraArgs     :: [String]
  , riThinkingFlags :: Map Int [String]
  , riProviderFlag  :: String
  , riModelFlag     :: String
  , riAgentFlag     :: String
  } deriving (Eq, Show)

data ParsedArgs = ParsedArgs
  { paRunner   :: Maybe String
  , paThinking :: Maybe Int
  , paProvider :: Maybe String
  , paModel    :: Maybe String
  , paAlias    :: Maybe String
  , paPrompt   :: String
  } deriving (Eq, Show)

data AliasDef = AliasDef
  { adRunner   :: Maybe String
  , adThinking :: Maybe Int
  , adProvider :: Maybe String
  , adModel    :: Maybe String
  , adAgent    :: Maybe String
  } deriving (Eq, Show)

data CccConfig = CccConfig
  { ccDefaultRunner   :: String
  , ccDefaultProvider :: String
  , ccDefaultModel    :: String
  , ccDefaultThinking :: Maybe Int
  , ccAliases         :: Map String AliasDef
  , ccAbbreviations   :: Map String String
  } deriving (Eq, Show)

runnerRegistry :: Map String RunnerInfo
runnerRegistry = Map.fromList $ baseRunners ++ abbrevs
  where
    opencode = RunnerInfo "opencode" ["run"] Map.empty "" "" "--agent"
    claude = RunnerInfo "claude" [] (Map.fromList
      [ (0, ["--no-thinking"])
      , (1, ["--thinking", "low"])
      , (2, ["--thinking", "medium"])
      , (3, ["--thinking", "high"])
      , (4, ["--thinking", "max"])
      ]) "" "--model" "--agent"
    kimi = RunnerInfo "kimi" [] (Map.fromList
      [ (0, ["--no-think"])
      , (1, ["--think", "low"])
      , (2, ["--think", "medium"])
      , (3, ["--think", "high"])
      , (4, ["--think", "max"])
      ]) "" "--model" "--agent"
    codex = RunnerInfo "codex" [] Map.empty "" "--model" ""
    roocode = RunnerInfo "roocode" [] Map.empty "" "--model" ""
    crush = RunnerInfo "crush" [] Map.empty "" "" ""

    baseRunners =
      [ ("opencode", opencode)
      , ("claude", claude)
      , ("kimi", kimi)
      , ("codex", codex)
      , ("roocode", roocode)
      , ("crush", crush)
      ]

    abbrevs =
      [ ("oc", opencode)
      , ("cc", claude)
      , ("c", codex)
      , ("cx", codex)
      , ("k", kimi)
      , ("rc", roocode)
      , ("cr", crush)
      ]

defaultConfig :: CccConfig
defaultConfig = CccConfig "oc" "" "" Nothing Map.empty Map.empty

runnerSelectorSet :: [String]
runnerSelectorSet =
  ["oc","cc","c","cx","k","rc","cr","codex","claude","opencode","kimi","roocode","crush","pi"]

isRunnerSelector :: String -> Bool
isRunnerSelector t = map toLower t `elem` runnerSelectorSet

matchThinking :: String -> Maybe Int
matchThinking ('+':[d])
  | d >= '0' && d <= '4' = Just (fromEnum d - fromEnum '0')
matchThinking _ = Nothing

isAsciiAlphaNum :: Char -> Bool
isAsciiAlphaNum c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

matchProviderModel :: String -> Maybe (String, String)
matchProviderModel (':':rest) = case break (== ':') rest of
  (provider, ':':model) ->
    let okProvider = not (null provider) && all (\c -> isAsciiAlphaNum c || c == '-' || c == '_') provider
        okModel   = not (null model)    && all (\c -> isAsciiAlphaNum c || c == '.' || c == '-' || c == '_') model
    in if okProvider && okModel then Just (provider, model) else Nothing
  _ -> Nothing
matchProviderModel _ = Nothing

matchModel :: String -> Maybe String
matchModel (':':model) =
  let ok = not (null model) && all (\c -> isAsciiAlphaNum c || c == '.' || c == '-' || c == '_') model
  in if ok then Just model else Nothing
matchModel _ = Nothing

matchAlias :: String -> Maybe String
matchAlias ('@':alias) =
  let ok = not (null alias) && all (\c -> isAsciiAlphaNum c || c == '-' || c == '_') alias
  in if ok then Just alias else Nothing
matchAlias _ = Nothing

parseArgs :: [String] -> ParsedArgs
parseArgs = go (ParsedArgs Nothing Nothing Nothing Nothing Nothing "") []
  where
    go parsed positional [] = parsed { paPrompt = unwords positional }
    go parsed positional (token:tokens)
      | isRunnerSelector token
      , Nothing <- paRunner parsed
      , null positional =
          go parsed { paRunner = Just (map toLower token) } positional tokens
      | Just n <- matchThinking token
      , null positional =
          go parsed { paThinking = Just n } positional tokens
      | Just (prov, mod) <- matchProviderModel token
      , null positional =
          go parsed { paProvider = Just prov, paModel = Just mod } positional tokens
      | Just mod <- matchModel token
      , null positional =
          go parsed { paModel = Just mod } positional tokens
      | Just alias <- matchAlias token
      , Nothing <- paAlias parsed
      , null positional =
          go parsed { paAlias = Just alias } positional tokens
      | otherwise =
          go parsed (positional ++ [token]) tokens

strip :: String -> String
strip = dropWhileEnd isSpace . dropWhile isSpace

resolveRunnerName :: Maybe String -> CccConfig -> String
resolveRunnerName Nothing config    = ccDefaultRunner config
resolveRunnerName (Just name) config =
  case Map.lookup name (ccAbbreviations config) of
    Just abbrev -> abbrev
    Nothing     -> name

nonEmpty :: String -> Maybe String
nonEmpty s
  | null s    = Nothing
  | otherwise = Just s

resolveCommand :: ParsedArgs -> Maybe CccConfig -> Either String ([String], Map String String, [String])
resolveCommand parsed mConfig =
  let
    config = fromMaybe defaultConfig mConfig
    warnings = []

    runnerName = resolveRunnerName (paRunner parsed) config

    opencodeInfo = runnerRegistry Map.! "opencode"
    info = fromMaybe opencodeInfo $
      Map.lookup runnerName runnerRegistry <|>
      Map.lookup (ccDefaultRunner config) runnerRegistry

    aliasDef = paAlias parsed >>= \a -> Map.lookup a (ccAliases config)

    effectiveInfo = case (aliasDef >>= adRunner, paRunner parsed) of
      (Just ar, Nothing) ->
        let name = resolveRunnerName (Just ar) config
        in fromMaybe info (Map.lookup name runnerRegistry)
      _ -> info

    baseArgv = riBinary effectiveInfo : riExtraArgs effectiveInfo

    effectiveThinking =
      paThinking parsed <|>
      (aliasDef >>= adThinking) <|>
      ccDefaultThinking config

    argvWithThinking = case effectiveThinking of
      Just n  -> case Map.lookup n (riThinkingFlags effectiveInfo) of
        Just flags -> baseArgv ++ flags
        Nothing    -> baseArgv
      Nothing -> baseArgv

    effectiveProvider =
      paProvider parsed <|>
      (aliasDef >>= adProvider) <|>
      nonEmpty (ccDefaultProvider config)

    effectiveModel =
      paModel parsed <|>
      (aliasDef >>= adModel) <|>
      nonEmpty (ccDefaultModel config)

    effectiveAgent = case paAlias parsed of
      Nothing    -> Nothing
      Just alias ->
        case aliasDef >>= adAgent of
          Just agent -> Just agent
          Nothing    -> if Map.member alias (ccAliases config) then Nothing else Just alias

    argvWithModel = case effectiveModel of
      Just m | not (null (riModelFlag effectiveInfo)) ->
        argvWithThinking ++ [riModelFlag effectiveInfo, m]
      _ -> argvWithThinking

    (argvWithAgent, warnings') = case effectiveAgent of
      Just agent | not (null (riAgentFlag effectiveInfo)) ->
        (argvWithModel ++ [riAgentFlag effectiveInfo, agent], warnings)
      Just agent ->
        let warning = "warning: runner \"" ++ riBinary effectiveInfo ++ "\" does not support agents; ignoring @" ++ agent
        in (argvWithModel, warnings ++ [warning])
      Nothing -> (argvWithModel, warnings)

    envOverrides = case effectiveProvider of
      Just p  -> Map.singleton "CCC_PROVIDER" p
      Nothing -> Map.empty

    prompt = strip (paPrompt parsed)
  in
    if null prompt
      then Left "prompt must not be empty"
      else Right (argvWithAgent ++ [prompt], envOverrides, warnings')
