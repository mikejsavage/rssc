import Control.Applicative
import Control.Concurrent
import Control.Exception
import Control.Monad

import Data.Maybe
import Data.List

import System.Locale
import Data.Time.Format
import Data.Time.Clock.POSIX

import qualified Data.ByteString.Lazy.Char8 as L
import qualified Network.HTTP.Client as Client
import Network.HTTP.Conduit

import Database.HDBC
import Database.HDBC.Sqlite3

import Text.XML.Light

data Feed = Feed String String String [ Story ] deriving Show
data Story = Story {
	title :: String,
	link :: String,
	date :: Integer,
	body :: String,
	guid :: String } deriving Show

urlsPath = "/etc/rssc.conf"
dbPath = "/var/lib/rss/feeds.sq3"

initDB db = do
	run db "CREATE TABLE IF NOT EXISTS feeds (\
		\id INTEGER PRIMARY KEY,\
		\url STRING NOT NULL,\
		\title STRING,\
		\link STRING,\
		\UNIQUE ( url ) ON CONFLICT IGNORE\
	\)" [ ]

	run db "CREATE TABLE IF NOT EXISTS articles (\
		\id INTEGER PRIMARY KEY,\
		\feedid INTEGER NOT NULL,\
		\guid INTEGER NOT NULL,\
		\title STRING NOT NULL,\
		\url STRING NOT NULL,\
		\content STRING NOT NULL,\
		\timestamp INTEGER NOT NULL,\
		\unread BOOLEAN DEFAULT 1,\
		\FOREIGN KEY ( feedid ) REFERENCES feeds ( id ),\
		\UNIQUE ( feedid, guid ) ON CONFLICT IGNORE\
	\)" [ ]

	run db "CREATE INDEX IF NOT EXISTS idx_feeds_title ON feeds ( title )" [ ]
	run db "CREATE INDEX IF NOT EXISTS idx_articles_timestamp on articles ( timestamp )" [ ]

	run db "PRAGMA foreign_keys = ON" [ ]

	commit db

addStory :: Connection -> SqlValue -> Story -> IO Integer
addStory db id story = do
	run db "INSERT INTO articles ( feedid, guid, title, url, content, timestamp ) VALUES ( ?, ?, ?, ?, ?, ? )" [
		id,
		toSql $ guid story,
		toSql $ title story,
		toSql $ link story,
		toSql $ body story,
		toSql $ date story ]

idFromUrl :: Connection -> String -> IO SqlValue
idFromUrl db url = do
	run db "INSERT INTO feeds ( url, title ) VALUES ( ?, ? )" [ toSql url, toSql url ]
	rows <- quickQuery' db "SELECT id FROM feeds WHERE url = ? LIMIT 1" [ toSql url ]

	let
		row = listToMaybe rows
		id = row >>= return . head

	case id of
		Just n -> return n
		Nothing -> return SqlNull

updateFeed :: Connection -> Feed -> IO ()
updateFeed db ( Feed url title link stories ) = do
	id <- idFromUrl db url

	run db "UPDATE feeds SET title = ?, link = ? WHERE id = ?" [ toSql title, toSql link, id ]

	foldM ( \_ story -> addStory db id story ) 0 stories
	commit db

rssTimeFormats :: [ String ]
rssTimeFormats = [
	"%a, %_d %b %Y %_H:%M:%S %Z",
	"%a, %_d %b %Y %_H:%M:%S",
	"%d %b %Y %_H:%M:%S %Z",
	"%d %b %Y %_H:%M:%S" ]

atomTimeFormats :: [ String ]
atomTimeFormats = [
	"%Y-%m-%dT%H:%M:%S%Q%Z",
	"%Y-%m-%dT%H:%M:%S%Q" ]

parseDate :: [ String ] -> String -> Maybe Integer
parseDate formats date =
	let
		parsed = map ( \form -> parseTime defaultTimeLocale form date ) formats
		first = listToMaybe $ catMaybes parsed
	in first >>= return . toInteger . round . utcTimeToPOSIXSeconds

findChildS :: String -> Element -> Maybe Element
findChildS name elem = findChild ( QName name Nothing Nothing ) elem

findChildrenS :: String -> Element -> [ Element ]
findChildrenS name elem = findChildren ( QName name Nothing Nothing ) elem

childText :: String -> Element -> Maybe String
childText name elem = findChildS name elem >>= ( return . strContent )

filterAlternate elem = qName ( elName elem ) == "link" && rel == Just "alternate"
	where
		rel = findAttr ( QName "rel" Nothing Nothing ) elem
		
atomLink :: Element -> Maybe String
atomLink elem = do
	child <- filterChild filterAlternate elem
	findAttr ( QName "href" Nothing Nothing ) child

parseItem :: Element -> Maybe Story
parseItem xml = do
	title <- childText "title" xml
	link <- childText "link" xml
	date <- childText "pubDate" xml >>= parseDate rssTimeFormats
	body <- childText "description" xml

	let guid = fromMaybe link ( childText "guid" xml )

	return Story {
		title = title,
		link = link,
		date = date,
		body = body,
		guid = guid }

parseRSS :: String -> Element -> Maybe Feed
parseRSS url xml = do
	channel <- findChildS "channel" xml

	let
		title = fromMaybe url $ childText "title" channel
		link = fromMaybe "" $ childText "link" channel

		items = findChildrenS "item" channel
		stories = catMaybes $ map parseItem items

	return $ Feed url title link stories

parseEntry :: Element -> Maybe Story
parseEntry xml = do
	title <- childText "title" xml
	link <- atomLink xml
	date <- childText "updated" xml >>= parseDate atomTimeFormats
	body <- childText "content" xml

	let guid = fromMaybe link ( childText "guid" xml )

	return Story {
		title = title,
		link = link,
		date = date,
		body = body,
		guid = guid }

parseAtom :: String -> Element -> Maybe Feed
parseAtom url xml = do
	return $ Feed url title link stories

	where
		title = fromMaybe url $ childText "title" xml
		link = fromMaybe "" $ childText "link" xml

		entries = findChildrenS "entry" xml
		stories = catMaybes $ map parseEntry entries


parseFeed :: ( String, String ) -> Maybe Feed
parseFeed ( url, feed ) = rssParsed <|> atomParsed
	where
		xml = parseXML feed
		elems = onlyElems xml

		rss = find ( ( == "rss" ) . qName . elName ) elems
		rssParsed = rss >>= parseRSS url

		atom = find ( ( == "feed" ) . qName . elName ) elems
		atomParsed = atom >>= parseAtom url

parseFeeds :: [ ( String, String ) ] -> [ Feed ]
parseFeeds feeds = catMaybes $ map parseFeed feeds

ignoreException :: SomeException -> IO String
ignoreException e = do
	print e
	return ""

downloadFeed :: String -> IO ( MVar String )
downloadFeed url = do
	sem <- newEmptyMVar
	forkIO $ do
		body <- ( simpleHttp url >>= return . L.unpack ) `catch` ignoreException
		putMVar sem body
	return sem

processFeeds :: Connection -> IO [ () ]
processFeeds db = do
	contents <- readFile urlsPath

	let urls = lines contents

	sems <- mapM downloadFeed urls
	feeds <- mapM takeMVar sems

	let parsed = parseFeeds ( zip urls feeds )
	mapM ( updateFeed db ) parsed

main :: IO ()
main = do
	db <- connectSqlite3 dbPath
	initDB db
	processFeeds db
	disconnect db
