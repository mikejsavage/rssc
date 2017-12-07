local xml = require( "xml" )
local xml_handler = require( "handler" )
local sqlite = require( "sqlite" )

if #arg > 1 then
	io.stderr:write( "usage: rssc [/path/to/db.sq3]\n" )
	return 1
end

local db_path = arg[ 1 ] or "/var/lib/rss/feeds.sq3"
local urls_path = "/etc/rssc.conf"

function io.readfile( path )
	local file = assert( io.open( path, "r" ) )
	local contents = assert( file:read( "*a" ) )
	assert( file:close() )
	return contents
end

local feeds = io.readfile( urls_path )

local db = sqlite.open( db_path )

db:run( [[
CREATE TABLE IF NOT EXISTS feeds (
	id INTEGER PRIMARY KEY,
	url STRING NOT NULL,
	title STRING,
	link STRING,
	UNIQUE ( url ) ON CONFLICT IGNORE
)]] )

db:run( [[
CREATE TABLE IF NOT EXISTS articles (
	id INTEGER PRIMARY KEY,
	feedid INTEGER NOT NULL,
	guid INTEGER NOT NULL,
	title STRING NOT NULL,
	url STRING NOT NULL,
	content STRING NOT NULL,
	timestamp INTEGER NOT NULL,
	unread BOOLEAN DEFAULT 1,
	FOREIGN KEY ( feedid ) REFERENCES feeds ( id ),
	UNIQUE ( feedid, guid ) ON CONFLICT IGNORE
)]] )

db:run( "CREATE INDEX IF NOT EXISTS idx_feeds_title ON feeds ( title )" )
db:run( "CREATE INDEX IF NOT EXISTS idx_articles_timestamp on articles ( timestamp )" )

db:run( "PRAGMA foreign_keys = ON" )

local function GET( url, num_redirects )
	local pipe = assert( io.popen( "curl --silent --location --max-redirs 5 --http1.1 --fail " .. url, "r" ) )
	local body = assert( pipe:read( "*all" ) )
	assert( pipe:close(), "curl failed" )
	return body
end

local function get_feed_id( title, url )
	db:run( "INSERT INTO feeds ( url, title ) VALUES ( ?, ? )", url, title )
	local id = db:first( "SELECT id FROM feeds WHERE url = ?", url ).id
	db:run( "UPDATE feeds SET title = ? WHERE id = ?", title, id )
	return id
end

local function add_story( feed_id, guid, title, url )
	db:run( "INSERT INTO articles ( feedid, guid, title, url, content, timestamp ) VALUES ( ?, ?, ?, ?, \"\", 0 )",
		feed_id, guid, title, url )
end

local function text( node )
	if node then
		return node[ 1 ] or node
	end
end

local function update_rss( url, rss )
	local channel = rss.channel
	local feed_title = text( channel.title ) or url
	local feed_url = text( channel.link ) or url
	local feed_id = get_feed_id( feed_title, feed_url )

	for _, story in ipairs( channel.item ) do
		-- local date = story.pubDate or story.date
		-- local content = story.description

		local url = text( story.link )
		local guid = text( story.guid )
		url = url or guid
		guid = guid or url
		assert( url, "no url" )

		local title = text( story.title ) or url

		add_story( feed_id, guid, title, url )
	end
end

local function parse_atom_link( link )
	if link._attr then
		return link._attr.href
	end

	for _, x in ipairs( link ) do
		if x._attr.rel == "alternate" then
			return x._attr.href
		end
	end

	for _, x in ipairs( link ) do
		if x._attr.href then
			return x._attr.href
		end
	end
end

local function update_atom( url, atom )
	local feed_title = text( atom.title ) or url
	local feed_url = parse_atom_link( atom.link ) or url
	local feed_id = get_feed_id( feed_title, feed_url )

	for _, story in ipairs( atom.entry ) do
		-- local date = story.updated
		-- local content = story.content or story.summary

		local url = parse_atom_link( story.link )
		local guid = text( story.guid )
		url = url or guid
		guid = guid or url
		assert( url, "no url" )

		local title = text( story.title ) or url

		print( feed_id, guid, title, url )
		add_story( feed_id, guid, title, url )
	end
end

local function update_feed( url )
	local body, err = GET( url )
	assert( body, err )

	local parser = xmlParser( simpleTreeHandler() )
	parser:parse( body )
	local parsed = parser._handler.root

	local rss = parsed.rss or parsed.RDF
	local atom = parsed.feed
	assert( rss or atom, "can't find a feed" )

	if rss then
		update_rss( url, rss )
	else
		update_atom( url, atom )
	end
end

local function on_error( message )
	return debug.traceback( message, 2 )
end

for url in feeds:gmatch( "%S+" ) do
	print( "Updating " .. url )
	local ok, err = xpcall( update_feed, on_error, url )
	if not ok then
		io.stderr:write( "Updating " .. url .. " failed: " .. err .. "\n" )
	end
end
