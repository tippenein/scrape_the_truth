{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE EmptyDataDecls             #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
module Database where

import Data.Aeson
import Data.Int (Int64)
import Data.Text (Text, unpack)
import Data.Time.Calendar (Day)
import Database.Esqueleto
import qualified Database.Persist as P
import Database.Persist.Sqlite hiding ((==.))
import Database.Persist.TH
import GHC.Generics hiding (from)

import Politifact.Scraper

dbName :: FilePath
dbName = "statements.db"

runDb = runSqlite "statements.db"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Person sql=persons
    name Text
    UniquePersonName name
    deriving Eq Show Generic

PersonStatement json sql=person_statements
    person PersonId
    truthValue Text
    statedOn Day
    statementLink Text
    UniqueStatement person statementLink
    deriving Eq Show Generic

StatementContent json sql=statement_bodies
    personStatement PersonStatementId
    synopsis Text
|]

instance ToJSON (Entity Person) where
  toJSON (Entity pid (Person personName )) = object
    [ "id" .= pid
    , "name" .= personName
    ]

instance Ord PersonStatement where
  (PersonStatement _ t1 _ _ ) `compare` (PersonStatement _ t2 _ _) = t1 `compare` t2

migrateDb:: IO ()
migrateDb = do
  putStrLn "migrating database"
  runDb $ runMigration migrateAll

findOrCreatePersonByName :: Text -> IO (Key Person)
findOrCreatePersonByName name = do
  p <- runDb $ getBy $ UniquePersonName name
  case p of
    Nothing -> do
      personId <- runDb $ insert $ Person name
      putStrLn $ "inserted " ++ unpack name
      return personId
    Just (Entity personId _) -> return personId

findPersonMaybe :: Int64 -> IO (Maybe Person)
findPersonMaybe person_id =
  runDb $ get (toSqlKey person_id)

insertStatement :: PoliticalStatement -> IO ()
insertStatement s = do
  personId <- findOrCreatePersonByName (name s)
  _ <- runDb $ insertBy $ PersonStatement personId (truth s) (statedOn s) (statementLink s)
  return ()

insertStatements :: [PoliticalStatement] -> IO ()
insertStatements = mapM_ insertStatement

selectPersons :: IO [Entity Person]
selectPersons = runDb $ selectList [] []

selectStatementsByName :: Maybe Text -> IO (Maybe [PersonStatement])
selectStatementsByName person_name =
  case person_name of
    Nothing -> do
      g <- runDb $ selectList [] [LimitTo 25]
      return $ Just $ map entityVal g
    Just n -> do
      mperson <- runDb $ selectFirst [PersonName P.==. n] []
      case mperson of
        Nothing -> return Nothing
        Just (Entity i _) -> Just <$> selectStatements (fromSqlKey i)

selectStatements :: Int64 -> IO [PersonStatement]
selectStatements person_id = do
  statements <- runDb $
    select $ from $ \personStatement -> do
    let subquery =
          from $ \person_table -> do
          where_ (person_table ^. PersonId ==. val (toSqlKey person_id))
          return $ person_table ^. PersonId
    where_ (personStatement ^. PersonStatementPerson ==. sub_select subquery)
    groupBy (personStatement ^. PersonStatementTruthValue)
    return personStatement

  return $ map entityVal statements
