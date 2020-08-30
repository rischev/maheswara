{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Main where
import Data.Aeson
import Data.Aeson.Types
import qualified Data.Text as T
import qualified Data.ByteString.Lazy.Char8 as L8
import qualified Data.ByteString.Char8 as B8
import Network.HTTP.Client
import Network.HTTP.Client.TLS

import Prelude hiding (repeat)
import System.IO
import qualified Data.Map as Map
import Control.Monad
import Control.Monad.State
import Data.Maybe (fromJust, fromMaybe)

import Entities
import Handlers

fetchJSON :: Request -> Manager -> IO L8.ByteString
fetchJSON req man = do
  response <- httpLbs req man
  return (responseBody response)

run :: StateT Bot IO ()
run = do
  bot <- get
  let users = getUsers bot
      action = getAction bot
      help = getHelp bot
      repeat = getRepeat bot
      manager = getManager bot
      token = getToken bot
      offset = getOffset bot
  unless (action == Await) (replicateM_ (getRepeat' action) (lift (httpLbs (getEcho action) manager))
                             >> put (bot { getAction = Await, getOffset = offset + 1 })
                             >> run)
  upds <- lift $ fetchJSON (getUpdates offset token) manager
  let list = parseMaybe updates =<< decode upds
  when (list == Just []) (put (bot { getAction = Await }) >> run)
  let currentUpd = head (fromJust list)
      currentMsg = message currentUpd
      chatId = (_id (chat $ currentMsg))
      (newBot, newReq) = fromJust $ sendReply bot chatId mempty currentMsg 
      repeats = fromMaybe 1 (Map.lookup chatId (getUsers newBot))
  lift $ print newReq
  put newBot { getAction = Echo newReq repeats, getOffset = update_id currentUpd }
  run

main :: IO ()
main = do
  manager <- newManager tlsManagerSettings
  token' <- readFile "token"
  help' <- readFile "help"
  repeat' <- readFile "repeat"
  let token = init token'
      help = T.pack (init help')
      repeat = T.pack (init repeat')
      bot = Bot { getUsers = Map.empty
                , getAction = Await
                , getHelp = T.unpack help
                , getRepeat = T.unpack repeat
                , getManager = manager
                , getToken = token
                , getOffset = 0
                }
  initial <- fetchJSON (getUpdates 0 token) manager
  let offset = fromMaybe 0 $ fmap update_id (getLast (parseMaybe updates =<< decode initial))
  evalStateT run (bot { getOffset = offset })
