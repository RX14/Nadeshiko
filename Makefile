.POSIX:

DESTDIR =
PREFIX = /usr/local
BASEDIR = $(DESTDIR)$(PREFIX)

install: __phony
	mkdir -m 0755 -p "$(BASEDIR)/share/nadeshiko" "$(BASEDIR)/bin"
	cp -r lib modules exampleconf nadeshiko.sh nadeshiko-mpv.sh nadeshiko-do-postponed.sh "$(BASEDIR)/share/nadeshiko"
	ln -sf "$(PREFIX)/share/nadeshiko/nadeshiko.sh" "$(BASEDIR)/bin/nadeshiko"
	ln -sf "$(PREFIX)/share/nadeshiko/nadeshiko-mpv.sh" "$(BASEDIR)/bin/nadeshiko-mpv"
	ln -sf "$(PREFIX)/share/nadeshiko/nadeshiko-do-postponed.sh" "$(BASEDIR)/bin/nadeshiko-do-postponed"

uninstall: __phony
	rm -rf "$(BASEDIR)/share/nadeshiko"
	rm -f "$(BASEDIR)/bin/nadeshiko"
	rm -f "$(BASEDIR)/bin/nadeshiko-mpv"
	rm -f "$(BASEDIR)/bin/nadeshiko-do-postponed"

__phony:
