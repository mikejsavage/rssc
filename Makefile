rssc: src/*.lua
	lua merge.lua src main.lua > rssc
	chmod +x rssc

clean:
	rm -f rssc
