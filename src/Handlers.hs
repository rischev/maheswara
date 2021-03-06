{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns#-}
module Handlers where
import Entities
import qualified Data.Text as T
import qualified Data.ByteString.Lazy.Char8 as L8 ()
import Network.HTTP.Client
import Network.HTTP.Client.TLS ()
import Control.Applicative ((<|>))
import Data.Aeson
import qualified Data.Map as Map

getLast :: Maybe Updates -> Maybe Update
getLast Nothing = Nothing
getLast (Just []) = Nothing
getLast (Just x) = Just (last x)

getUpdates :: Offset -> String -> Maybe Request
getUpdates offset token = parseRequest (token <> "/getUpdates?timeout=10&offset=" <> show offset)

sendReply :: Bot -> Integer -> Maybe String -> Message -> Maybe (Bot, Request)
sendReply bot chatId _ msg = message' <|> audio' <|> document' <|> photo' <|> sticker' <|> video' <|> voice'
  where message' = sendMessage bot chatId Nothing <$> text msg
        audio' = sendMedia bot chatId (caption msg) "audio" <$> audio msg
        document' = sendMedia bot chatId (caption msg) "document" <$> document msg
        photo' = sendMedia bot chatId (caption msg) "photo" <$> fmap head (photo msg)
        sticker' = sendMedia bot chatId (caption msg) "sticker" <$> sticker msg
        video' = sendMedia bot chatId (caption msg) "video" <$> video msg
        voice' = sendMedia bot chatId (caption msg) "voice" <$> voice msg

composeMessage :: Integer -> T.Text -> Maybe KeyboardMarkup -> Value
composeMessage chatId text (Just markup) = object ["chat_id" .= chatId, "text" .= text, "reply_markup" .= markup]
composeMessage chatId text Nothing = object ["chat_id" .= chatId, "text" .= text]

sendMessage :: Bot -> Integer -> Maybe T.Text -> T.Text -> (Bot, Request)
sendMessage bot chatId _ x
  | (T.unpack -> "/help") <- x = (bot, req { requestBody = RequestBodyLBS $ encode $ composeMessage chatId (getHelp (getConfig bot)) Nothing })
  | (T.unpack -> "/repeat") <- x = (bot, req { requestBody = RequestBodyLBS $ encode $ composeMessage chatId (getHelp (getConfig bot)) (Just defaultKeyboard) })
  | x' <- x = case T.uncons x' of
                Just ('/', xs) -> (bot { getUsers = Map.insert chatId (read $ T.unpack xs) (getUsers bot) }
                                  , req { requestBody = RequestBodyLBS $ encode $ composeMessage chatId (T.pack "Reply count set to " <> xs) Nothing })
                Just _         -> (bot, req { requestBody = RequestBodyLBS $ encode $ composeMessage chatId x Nothing})
                Nothing        -> (bot, req)
  where req = request' (getTokenTG (getConfig bot)) "/sendMessage"

composeMedia :: Integer -> Maybe T.Text -> T.Text -> Media -> Value
composeMedia chatId (Just caption) name (Media fileId) = object ["chat_id" .= chatId, name .= fileId, "caption" .= caption]
composeMedia chatId Nothing name (Media fileId) = object ["chat_id" .= chatId, name .= fileId]

sendMedia :: Bot -> Integer -> Maybe T.Text -> String -> Media -> (Bot, Request)
sendMedia bot chatId caption name media = (bot, req { requestBody = RequestBodyLBS $ encode
                                                    $ composeMedia chatId caption (T.pack name) media })
  where req = request' (getTokenTG (getConfig bot)) ("/send" <> name)

request' :: Token -> String -> Request
request' token path =
  (parseRequest_ $ token <> path) {
   method = "POST",
   requestHeaders = [("Content-Type", "application/json; charset=utf-8")] }
