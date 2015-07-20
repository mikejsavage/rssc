[1]: https://github.com/mikejsavage/rssc-sendmail

rssc scrapes a list of RSS or Atom feeds into an SQLite database and
then exits. It is not designed to be used by itself - and users
attempting to do will be underwhelmed - but paired with cron and a
frontend of some sort. (for example [rssc-sendmail][1])

Dependencies
------------

haskell, hdbc-sqlite3, http-conduit, xml

Usage
-----

Building:

	$ git clone https://github.com/mikejsavage/rssc
	$ make
	$ make install

To run (in this case every 15 minutes), add an entry like the following
to your crontab:

	*/15 * * * * rssc

`make install` will create an unprivileged `rssc` user for you and
chown its data directory, so I recommend you add the above to `rssc`'s
crontab and not root's.

Configuration
-------------

The only configuration rssc needs is a list of feeds to scrape. It looks
for these in `/etc/rssc.conf`, which should contain a single URL per
line. For example:

	http://what-if.xkcd.com/feed.atom
	http://xkcd.com/rss.xml
	http://www.joelonsoftware.com/rss.xml
	http://undeadly.org/cgi?action=rss
	...
