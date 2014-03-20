SOURCES = $(wildcard src/**/*.hs src/*.hs)

TARGET = rssc

GHCARGS = -O

.PHONY: install clean

all: $(TARGET)

$(TARGET): $(SOURCES)
	ghc $(GHCARGS) --make $^ -o $(TARGET)

install:
	useradd -M -s /bin/false rssc
	mkdir /var/lib/rss
	chown rssc:rssc /var/lib/rss
	cp $(TARGET) /usr/bin

clean:
	rm -f src/*.o src/*.hi $(TARGET)
