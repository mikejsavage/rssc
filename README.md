[1]: https://github.com/mikejsavage/rssc-sendmail

rssc will scrape a list of RSS or Atom feeds into an SQLite database and
then exit. It is not designed to be used by itself - and users
attempting to do will be underwhelmed - but paired with cron and a
frontend of some sort. (for example [rssc-sendmail][1])

Dependencies
------------

haskell, hdbc-sqlite, http-conduit, xml

Usage
-----

Building:

	$ git clone https://github.com/mikejsavage/rssc
	$ make
	$ make install

To run (in this case every 15 minutes and as the `rssc` user), add an
entry like the following to your crontab:

	*/15 * * * * rssc rssc

Configuration
-------------

The only configuration rssc needs is a list of feeds to scrape. It
searches for these in `/etc/rssc.conf`. It expects a single URL per
line. For example:

	http://what-if.xkcd.com/feed.atom
	http://xkcd.com/rss.xml
	http://www.joelonsoftware.com/rss.xml
	http://undeadly.org/cgi?action=rss
	...
