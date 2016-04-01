{-# LANGUAGE OverloadedStrings #-}
module Server (runServer, app) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Either
import Data.Text (Text)
import Network.Wai
import Network.Wai.Handler.Warp
import Network.Wai.Middleware.Cors
import Network.Wai.Middleware.RequestLogger (logStdout)
import Servant

import Api
import Database

server :: Server TruthApi
server =
       listPersons
  :<|> listStatements

type Handler a = EitherT ServantErr IO a

listPersons :: Handler [Person]
listPersons =
  liftIO Database.selectPersons

listStatements :: Maybe Text -> Handler [PersonStatement]
listStatements name = do
  ms <- liftIO $ Database.selectStatements name
  return $ ms

middlewares = simpleCors . logStdout

app :: Application
app = middlewares $ serve Api.truthApi server

runServer :: Port -> IO ()
runServer port = run port app
