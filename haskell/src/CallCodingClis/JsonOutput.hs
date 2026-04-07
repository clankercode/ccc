{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module CallCodingClis.JsonOutput
  ( ToolCall(..)
  , ToolResult(..)
  , JsonEvent(..)
  , ParsedJsonOutput(..)
  , parseOpencodeJson
  , parseClaudeCodeJson
  , parseKimiJson
  , parseJsonOutput
  , renderParsed
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString.Lazy.Char8 as BSL
import qualified Data.Text as T
import Data.Text (Text)
import Data.Char (isSpace)
import Data.List (dropWhileEnd)
import Data.Maybe (fromMaybe, catMaybes)
import Data.Scientific (toBoundedInteger, toRealFloat)

data ToolCall = ToolCall
  { tcId        :: Text
  , tcName      :: Text
  , tcArguments :: Text
  } deriving (Eq, Show)

data ToolResult = ToolResult
  { trToolCallId :: Text
  , trContent    :: Text
  , trIsError    :: Bool
  } deriving (Eq, Show)

data JsonEvent = JsonEvent
  { jeEventType  :: Text
  , jeText       :: Text
  , jeThinking   :: Text
  , jeToolCall   :: Maybe ToolCall
  , jeToolResult :: Maybe ToolResult
  , jeRaw        :: Aeson.Object
  } deriving (Eq, Show)

data ParsedJsonOutput = ParsedJsonOutput
  { pjoSchemaName :: Text
  , pjoEvents     :: [JsonEvent]
  , pjoFinalText  :: Text
  , pjoSessionId  :: Text
  , pjoError      :: Text
  , pjoUsage      :: Aeson.Object
  , pjoCostUsd    :: Double
  , pjoDurationMs :: Int
  , pjoRawLines   :: [Aeson.Object]
  } deriving (Eq, Show)

emptyParsed :: Text -> ParsedJsonOutput
emptyParsed schema = ParsedJsonOutput schema [] "" "" "" KM.empty 0.0 0 []

objToStr :: Aeson.Value -> Text
objToStr (Aeson.String t) = t
objToStr v = T.pack (BSL.unpack (Aeson.encode v))

valToStr :: Maybe Aeson.Value -> Text
valToStr Nothing = ""
valToStr (Just (Aeson.String t)) = t
valToStr (Just v) = T.pack (BSL.unpack (Aeson.encode v))

valToFloat :: Maybe Aeson.Value -> Double
valToFloat Nothing = 0.0
valToFloat (Just (Aeson.Number n)) = toRealFloat n
valToFloat (Just (Aeson.String _)) = 0.0
valToFloat (Just _) = 0.0

valToInt :: Maybe Aeson.Value -> Int
valToInt Nothing = 0
valToInt (Just (Aeson.Number n)) = case toBoundedInteger n of
  Just i -> i
  Nothing -> 0
valToInt _ = 0

valToBool :: Maybe Aeson.Value -> Bool
valToBool (Just (Aeson.Bool b)) = b
valToBool _ = False

lookupStr :: Aeson.Object -> Text -> Text
lookupStr obj key = valToStr (KM.lookup (Key.fromText key) obj)

lookupInt :: Aeson.Object -> Text -> Int
lookupInt obj key = valToInt (KM.lookup (Key.fromText key) obj)

lookupFloat :: Aeson.Object -> Text -> Double
lookupFloat obj key = valToFloat (KM.lookup (Key.fromText key) obj)

lookupBool :: Aeson.Object -> Text -> Bool
lookupBool obj key = valToBool (KM.lookup (Key.fromText key) obj)

lookupObj :: Aeson.Object -> Text -> Maybe Aeson.Object
lookupObj obj key = case KM.lookup (Key.fromText key) obj of
  Just (Aeson.Object o) -> Just o
  _ -> Nothing

lookupArr :: Aeson.Object -> Text -> Maybe [Aeson.Value]
lookupArr obj key = case KM.lookup (Key.fromText key) obj of
  Just (Aeson.Array a) -> Just (foldr (:) [] a)
  _ -> Nothing

getAsObj :: Aeson.Value -> Maybe Aeson.Object
getAsObj (Aeson.Object o) = Just o
getAsObj _ = Nothing

parseLines :: String -> [Maybe Aeson.Object]
parseLines raw = map parseLine (lines raw)
  where
    parseLine l =
      let l' = strip l
      in if null l' then Nothing
         else case Aeson.eitherDecode (BSL.pack l') of
           Right (Aeson.Object o) -> Just o
           _ -> Nothing

strip :: String -> String
strip = dropWhileEnd isSpace . dropWhile isSpace

parseOpencodeJson :: String -> ParsedJsonOutput
parseOpencodeJson raw = go (parseLines raw) (emptyParsed "opencode")
  where
    go [] acc = acc
    go (Nothing : rest) acc = go rest acc
    go (Just obj : rest) acc =
      let acc' = acc { pjoRawLines = pjoRawLines acc ++ [obj] }
      in case (KM.lookup (Key.fromText "response") obj, KM.lookup (Key.fromText "error") obj) of
        (Just val, _) ->
          let text = objToStr val
          in go rest acc' { pjoFinalText = text
                          , pjoEvents = pjoEvents acc' ++ [JsonEvent "text" text "" Nothing Nothing obj] }
        (_, Just val) ->
          let errMsg = objToStr val
          in go rest acc' { pjoError = errMsg
                          , pjoEvents = pjoEvents acc' ++ [JsonEvent "error" errMsg "" Nothing Nothing obj] }
        _ -> go rest acc'

parseClaudeCodeJson :: String -> ParsedJsonOutput
parseClaudeCodeJson raw = go (parseLines raw) (emptyParsed "claude-code")
  where
    go [] acc = acc
    go (Nothing : rest) acc = go rest acc
    go (Just obj : rest) acc =
      let acc' = acc { pjoRawLines = pjoRawLines acc ++ [obj] }
          msgType = lookupStr obj "type"
      in go rest (dispatchClaude msgType obj acc')

dispatchClaude :: Text -> Aeson.Object -> ParsedJsonOutput -> ParsedJsonOutput
dispatchClaude "system" obj acc =
  case lookupStr obj "subtype" of
    "init" -> acc { pjoSessionId = lookupStr obj "session_id" }
    "api_retry" -> appendEvent acc (JsonEvent "system_retry" "" "" Nothing Nothing obj)
    _ -> acc

dispatchClaude "assistant" obj acc =
  let message = fromMaybe KM.empty (lookupObj obj "message")
      contentArr = fromMaybe [] (lookupArr message "content")
      texts = [t | Just b <- map getAsObj contentArr
                  , lookupStr b "type" == "text"
                  , let t = lookupStr b "text", not (T.null t)]
      acc' = if null texts then acc
             else let text = T.intercalate "\n" texts
                  in acc { pjoFinalText = text
                         , pjoEvents = pjoEvents acc ++ [JsonEvent "assistant" text "" Nothing Nothing obj] }
  in case KM.lookup (Key.fromText "usage") message of
    Just (Aeson.Object u) -> acc' { pjoUsage = u }
    _ -> acc'

dispatchClaude "stream_event" obj acc =
  case lookupObj obj "event" of
    Nothing -> acc
    Just event ->
      let evType = lookupStr event "type"
      in if evType == "content_block_delta"
         then case lookupObj event "delta" of
           Nothing -> acc
           Just delta ->
             let dType = lookupStr delta "type"
             in if dType == "text_delta"
                then appendEvent acc (JsonEvent "text_delta" (lookupStr delta "text") "" Nothing Nothing obj)
                else if dType == "thinking_delta"
                     then appendEvent acc (JsonEvent "thinking_delta" "" (lookupStr delta "thinking") Nothing Nothing obj)
                     else if dType == "input_json_delta"
                          then appendEvent acc (JsonEvent "tool_input_delta" (lookupStr delta "partial_json") "" Nothing Nothing obj)
                          else acc
         else if evType == "content_block_start"
              then case lookupObj event "content_block" of
                Nothing -> acc
                Just cb ->
                  let cbType = lookupStr cb "type"
                  in if cbType == "thinking"
                     then appendEvent acc (JsonEvent "thinking_start" "" "" Nothing Nothing obj)
                     else if cbType == "tool_use"
                          then let tc = ToolCall (lookupStr cb "id") (lookupStr cb "name") ""
                               in appendEvent acc (JsonEvent "tool_use_start" "" "" (Just tc) Nothing obj)
                          else acc
              else acc

dispatchClaude "tool_use" obj acc =
  let toolInput = case KM.lookup (Key.fromText "tool_input") obj of
        Just v -> T.pack (BSL.unpack (Aeson.encode v))
        Nothing -> "{}"
      tc = ToolCall "" (lookupStr obj "tool_name") toolInput
  in appendEvent acc (JsonEvent "tool_use" "" "" (Just tc) Nothing obj)

dispatchClaude "tool_result" obj acc =
  let tr = ToolResult (lookupStr obj "tool_use_id") (lookupStr obj "content") (lookupBool obj "is_error")
  in appendEvent acc (JsonEvent "tool_result" "" "" Nothing (Just tr) obj)

dispatchClaude "result" obj acc =
  case lookupStr obj "subtype" of
    "success" ->
      let r = lookupStr obj "result"
          ft = if T.null r then pjoFinalText acc else r
          usage' = case KM.lookup (Key.fromText "usage") obj of
            Just (Aeson.Object u) -> u
            _ -> pjoUsage acc
      in acc { pjoFinalText = ft
             , pjoCostUsd = lookupFloat obj "cost_usd"
             , pjoDurationMs = lookupInt obj "duration_ms"
             , pjoUsage = usage'
             , pjoEvents = pjoEvents acc ++ [JsonEvent "result" ft "" Nothing Nothing obj] }
    "error" ->
      let e = lookupStr obj "error"
      in acc { pjoError = e, pjoEvents = pjoEvents acc ++ [JsonEvent "error" e "" Nothing Nothing obj] }
    _ -> acc

dispatchClaude _ _ acc = acc

appendEvent :: ParsedJsonOutput -> JsonEvent -> ParsedJsonOutput
appendEvent acc ev = acc { pjoEvents = pjoEvents acc ++ [ev] }

passthroughTypes :: [Text]
passthroughTypes =
  [ "TurnBegin", "StepBegin", "StepInterrupted", "TurnEnd"
  , "StatusUpdate", "HookTriggered", "HookResolved"
  , "ApprovalRequest", "SubagentEvent", "ToolCallRequest"
  ]

parseKimiJson :: String -> ParsedJsonOutput
parseKimiJson raw = go (parseLines raw) (emptyParsed "kimi")
  where
    go [] acc = acc
    go (Nothing : rest) acc = go rest acc
    go (Just obj : rest) acc =
      let acc' = acc { pjoRawLines = pjoRawLines acc ++ [obj] }
          wireType = lookupStr obj "type"
      in if wireType `elem` passthroughTypes
         then go rest (appendEvent acc' (JsonEvent (T.toLower wireType) "" "" Nothing Nothing obj))
         else go rest (dispatchKimi obj acc')

dispatchKimi :: Aeson.Object -> ParsedJsonOutput -> ParsedJsonOutput
dispatchKimi obj acc =
  let role = lookupStr obj "role"
  in if role == "assistant"
     then let acc' = kimiAssistantContent obj acc
          in kimiToolCalls obj acc'
     else if role == "tool"
          then kimiToolResult obj acc
          else acc

kimiAssistantContent :: Aeson.Object -> ParsedJsonOutput -> ParsedJsonOutput
kimiAssistantContent obj acc =
  case KM.lookup (Key.fromText "content") obj of
    Just (Aeson.String s) ->
      acc { pjoFinalText = s
          , pjoEvents = pjoEvents acc ++ [JsonEvent "assistant" s "" Nothing Nothing obj] }
    Just (Aeson.Array arr) ->
      let (texts, evts) = foldr collectText ([], []) (foldr (:) [] arr)
      in let text = T.intercalate "\n" (reverse texts)
             acc' = if null texts then acc
                    else acc { pjoFinalText = text
                             , pjoEvents = pjoEvents acc ++ [JsonEvent "assistant" text "" Nothing Nothing obj] }
         in acc' { pjoEvents = pjoEvents acc' ++ reverse evts }
    _ -> acc
  where
    collectText (Aeson.Object part) (texts, evts) =
      case lookupStr part "type" of
        "text" -> (lookupStr part "text" : texts, evts)
        "think" -> (texts, JsonEvent "thinking" "" (lookupStr part "think") Nothing Nothing obj : evts)
        _ -> (texts, evts)
    collectText _ acc' = acc'

kimiToolCalls :: Aeson.Object -> ParsedJsonOutput -> ParsedJsonOutput
kimiToolCalls obj acc =
  case lookupArr obj "tool_calls" of
    Nothing -> acc
    Just tcs -> foldr processTc acc tcs
  where
    processTc tcData a = case getAsObj tcData of
      Nothing -> a
      Just td ->
        let fn = fromMaybe KM.empty (lookupObj td "function")
            tc = ToolCall (lookupStr td "id") (lookupStr fn "name") (lookupStr fn "arguments")
        in appendEvent a (JsonEvent "tool_call" "" "" (Just tc) Nothing obj)

kimiToolResult :: Aeson.Object -> ParsedJsonOutput -> ParsedJsonOutput
kimiToolResult obj acc =
  let content = fromMaybe [] (lookupArr obj "content")
      texts = [t | Aeson.Object part <- content
                  , lookupStr part "type" == "text"
                  , let t = lookupStr part "text"
                  , not (T.isPrefixOf "<system>" t)]
      tr = ToolResult (lookupStr obj "tool_call_id") (T.intercalate "\n" texts) False
  in appendEvent acc (JsonEvent "tool_result" "" "" Nothing (Just tr) obj)

parseJsonOutput :: String -> Text -> ParsedJsonOutput
parseJsonOutput raw schema
  | schema == "opencode" = parseOpencodeJson raw
  | schema == "claude-code" = parseClaudeCodeJson raw
  | schema == "kimi" = parseKimiJson raw
  | otherwise = (emptyParsed schema) { pjoError = "unknown schema: " <> schema }

renderParsed :: ParsedJsonOutput -> Text
renderParsed output =
  let parts = foldr renderEvent [] (pjoEvents output)
  in if null parts then pjoFinalText output else T.intercalate "\n" parts
  where
    renderEvent ev acc = case jeEventType ev of
      t | t `elem` ["text", "assistant", "result"] ->
        if T.null (jeText ev) then acc else jeText ev : acc
      t | t `elem` ["thinking_delta", "thinking"] ->
        if T.null (jeThinking ev) then acc else ("[thinking] " <> jeThinking ev) : acc
      "tool_use" -> case jeToolCall ev of
        Just tc -> ("[tool] " <> tcName tc) : acc
        Nothing -> acc
      "tool_result" -> case jeToolResult ev of
        Just tr -> ("[tool_result] " <> trContent tr) : acc
        Nothing -> acc
      "error" ->
        if T.null (jeText ev) then acc else ("[error] " <> jeText ev) : acc
      _ -> acc
