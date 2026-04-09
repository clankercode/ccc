module CallCodingClis.Parser where

import Prelude

import CallCodingClis.Config (CccConfig)
import CallCodingClis.Types (CommandSpec)
import Data.Array (uncons)
import Data.Foldable (any, foldl)
import Data.Maybe (Maybe(..))
import Data.String (trim)
import Data.String.CodeUnits as CU
import Data.String.Pattern (Pattern(..))
import Data.String.Common (split)
import Foreign.Object as Object

type ParsedArgs =
  { runner :: Maybe String
  , thinking :: Maybe Int
  , provider :: Maybe String
  , model :: Maybe String
  , alias :: Maybe String
  , prompt :: String
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
    [ "oc", "cc", "c", "k", "rc", "cr"
    , "codex", "claude", "opencode", "kimi", "roocode", "crush", "pi"
    ]

normalizeRunner :: String -> String
normalizeRunner token = case token of
  "OC" -> "oc"
  "CC" -> "cc"
  "C" -> "c"
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

resolveCommand :: ParsedArgs -> CccConfig -> CommandSpec
resolveCommand parsed config =
  let
    runnerName = case parsed.runner of
      Just runner -> resolveRunnerName runner
      Nothing -> resolveRunnerName config.defaultRunner
    prompt = trim parsed.prompt
    argv = case runnerName of
      "opencode" -> ["opencode", "run", prompt]
      "claude" -> ["claude", prompt]
      "kimi" -> ["kimi", prompt]
      "codex" -> ["codex", prompt]
      "crush" -> ["crush", prompt]
      other -> [other, prompt]
  in
    { argv
    , stdinText: Nothing
    , cwd: Nothing
    , env: Object.empty
    }

resolveRunnerName :: String -> String
resolveRunnerName name = case normalizeRunner name of
  "oc" -> "opencode"
  "cc" -> "claude"
  "c" -> "claude"
  "k" -> "kimi"
  "rc" -> "codex"
  "cr" -> "crush"
  other -> other
