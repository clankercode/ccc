module CallCodingClis.Parser
  ( ParsedArgs(..)
  , ResolvedCommand
  , parseArgs
  , resolveCommand
  , resolveRunnerName
  ) where

import Prelude

import CallCodingClis.Config (CccConfig)
import Data.Array (uncons)
import Data.Foldable (any, foldl)
import Data.Maybe (Maybe(..))
import Data.String (trim)
import Data.String.CodeUnits as CU
import Data.String.Common (split)
import Data.String.Pattern (Pattern(..))
import Data.Tuple (Tuple(..))
import Foreign.Object as Object

type ParsedArgs =
  { runner :: Maybe String
  , thinking :: Maybe Int
  , provider :: Maybe String
  , model :: Maybe String
  , alias :: Maybe String
  , prompt :: String
  }

type ResolvedCommand =
  { argv :: Array String
  , env :: Object.Object String
  , warnings :: Array String
  }

type RunnerSpec =
  { binary :: String
  , extraArgs :: Array String
  , modelFlag :: String
  , agentFlag :: String
  }

parseArgs :: Array String -> ParsedArgs
parseArgs argv = go argv Nothing Nothing Nothing Nothing Nothing []
  where
  go rest runner thinking provider model alias positional =
    case uncons rest of
      Nothing ->
        { runner
        , thinking
        , provider
        , model
        , alias
        , prompt: trim (joinWords positional)
        }
      Just { head: token, tail: more }
        | isRunner token && runner == Nothing && positional == [] ->
            go more (Just (normalizeRunner token)) thinking provider model alias positional
        | isThinkingToken token && positional == [] ->
            go more runner (parseThinking token) provider model alias positional
        | isProviderModelToken token && positional == [] ->
            case splitProviderModel token of
              Just { prov, mdl } -> go more runner thinking (Just prov) (Just mdl) alias positional
              Nothing -> go more runner thinking provider model alias (positional <> [token])
        | isModelToken token && positional == [] ->
            go more runner thinking provider (Just (CU.drop 1 token)) alias positional
        | isAliasToken token && alias == Nothing && positional == [] ->
            go more runner thinking provider model (Just (CU.drop 1 token)) positional
        | otherwise ->
            go more runner thinking provider model alias (positional <> [token])

  joinWords arr =
    case uncons arr of
      Nothing -> ""
      Just { head, tail } -> foldl (\acc word -> acc <> " " <> word) head tail

isRunner :: String -> Boolean
isRunner token =
  any (_ == normalizeRunner token)
    [ "oc", "cc", "c", "cx", "k", "rc", "cr"
    , "codex", "claude", "opencode", "kimi", "roocode", "crush", "pi"
    ]

normalizeRunner :: String -> String
normalizeRunner token = case token of
  "OC" -> "oc"
  "CC" -> "cc"
  "C" -> "c"
  "CX" -> "cx"
  "K" -> "k"
  "RC" -> "rc"
  "CR" -> "cr"
  "CODEX" -> "codex"
  "CLAUDE" -> "claude"
  "OPENCODE" -> "opencode"
  "KIMI" -> "kimi"
  "ROOCODE" -> "roocode"
  "CRUSH" -> "crush"
  "PI" -> "pi"
  other -> other

isThinkingToken :: String -> Boolean
isThinkingToken token =
  CU.indexOf (Pattern "+") token == Just 0 && CU.length token == 2 && parseThinking token /= Nothing

parseThinking :: String -> Maybe Int
parseThinking token = case CU.drop 1 token of
  "0" -> Just 0
  "1" -> Just 1
  "2" -> Just 2
  "3" -> Just 3
  "4" -> Just 4
  _ -> Nothing

isProviderModelToken :: String -> Boolean
isProviderModelToken token = case splitProviderModel token of
  Just _ -> true
  Nothing -> false

splitProviderModel :: String -> Maybe { prov :: String, mdl :: String }
splitProviderModel token =
  if CU.indexOf (Pattern ":") token /= Just 0 then Nothing
  else
    let rest = CU.drop 1 token
        parts = split (Pattern ":") rest
    in case parts of
         [prov, mdl] ->
           let p = trim prov
               m = trim mdl
           in if p == "" || m == "" then Nothing else Just { prov: p, mdl: m }
         _ -> Nothing

isModelToken :: String -> Boolean
isModelToken token =
  CU.indexOf (Pattern ":") token == Just 0 && not (isProviderModelToken token) && CU.length token > 1

isAliasToken :: String -> Boolean
isAliasToken token = CU.indexOf (Pattern "@") token == Just 0 && CU.length token > 1

resolveRunnerName :: String -> CccConfig -> String
resolveRunnerName name config =
  case Object.lookup name config.abbreviations of
    Just resolved -> resolveRunnerName resolved config
    Nothing ->
      case normalizeRunner name of
        "oc" -> "opencode"
        "cc" -> "claude"
        "c" -> "codex"
        "cx" -> "codex"
        "k" -> "kimi"
        "rc" -> "roocode"
        "cr" -> "crush"
        other -> other

runnerSpec :: String -> RunnerSpec
runnerSpec runnerName = case runnerName of
  "opencode" ->
    { binary: "opencode"
    , extraArgs: ["run"]
    , modelFlag: ""
    , agentFlag: "--agent"
    }
  "claude" ->
    { binary: "claude"
    , extraArgs: []
    , modelFlag: "--model"
    , agentFlag: "--agent"
    }
  "kimi" ->
    { binary: "kimi"
    , extraArgs: []
    , modelFlag: "--model"
    , agentFlag: "--agent"
    }
  "codex" ->
    { binary: "codex"
    , extraArgs: []
    , modelFlag: "--model"
    , agentFlag: ""
    }
  "roocode" ->
    { binary: "roocode"
    , extraArgs: []
    , modelFlag: ""
    , agentFlag: ""
    }
  "crush" ->
    { binary: "crush"
    , extraArgs: []
    , modelFlag: ""
    , agentFlag: ""
    }
  other ->
    { binary: other
    , extraArgs: []
    , modelFlag: ""
    , agentFlag: ""
    }

thinkingArgs :: String -> Maybe Int -> Array String
thinkingArgs runnerName thinking = case Tuple runnerName thinking of
  Tuple "claude" (Just 0) -> ["--no-thinking"]
  Tuple "claude" (Just 1) -> ["--thinking", "low"]
  Tuple "claude" (Just 2) -> ["--thinking", "medium"]
  Tuple "claude" (Just 3) -> ["--thinking", "high"]
  Tuple "claude" (Just 4) -> ["--thinking", "max"]
  Tuple "kimi" (Just 0) -> ["--no-think"]
  Tuple "kimi" (Just 1) -> ["--think", "low"]
  Tuple "kimi" (Just 2) -> ["--think", "medium"]
  Tuple "kimi" (Just 3) -> ["--think", "high"]
  Tuple "kimi" (Just 4) -> ["--think", "max"]
  Tuple _ _ -> []

resolveCommand :: ParsedArgs -> CccConfig -> ResolvedCommand
resolveCommand parsed config =
  let
    aliasDef = parsed.alias >>= \name -> Object.lookup name config.aliases
    selectedRunnerToken = case parsed.runner of
      Just runner -> runner
      Nothing -> case aliasDef >>= _.runner of
        Just aliasRunner -> aliasRunner
        Nothing -> config.defaultRunner
    runnerName = resolveRunnerName selectedRunnerToken config
    spec = runnerSpec runnerName

    effectiveThinking = case parsed.thinking of
      Just level -> Just level
      Nothing -> case aliasDef >>= _.thinking of
        Just level -> Just level
        Nothing -> config.defaultThinking

    effectiveProvider = case parsed.provider of
      Just provider -> Just provider
      Nothing -> case aliasDef >>= _.provider of
        Just provider -> Just provider
        Nothing -> nonEmpty config.defaultProvider

    effectiveModel = case parsed.model of
      Just model -> Just model
      Nothing -> case aliasDef >>= _.model of
        Just model -> Just model
        Nothing -> nonEmpty config.defaultModel

    effectiveAgent = case parsed.alias of
      Nothing -> Nothing
      Just aliasName ->
        case aliasDef >>= _.agent of
          Just agent -> Just agent
          Nothing -> Just aliasName

    argvWithRunner = [spec.binary] <> spec.extraArgs
    argvWithThinking = argvWithRunner <> thinkingArgs runnerName effectiveThinking
    argvWithModel = case effectiveModel of
      Just model | spec.modelFlag /= "" -> argvWithThinking <> [spec.modelFlag, model]
      _ -> argvWithThinking

    warnings = case effectiveAgent of
      Just agent | spec.agentFlag == "" ->
        [ "warning: runner \"" <> runnerName <> "\" does not support agents; ignoring @" <> agent ]
      _ -> []

    argvWithAgent = case effectiveAgent of
      Just agent | spec.agentFlag /= "" -> argvWithModel <> [spec.agentFlag, agent]
      _ -> argvWithModel

    envOverrides = case effectiveProvider of
      Just provider -> Object.singleton "CCC_PROVIDER" provider
      Nothing -> Object.empty

    prompt = trim parsed.prompt
  in
    { argv: argvWithAgent <> [prompt]
    , env: envOverrides
    , warnings
    }

nonEmpty :: String -> Maybe String
nonEmpty value = if value == "" then Nothing else Just value
