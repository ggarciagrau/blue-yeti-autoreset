CC ?= cc
PKG_CONFIG ?= pkg-config
INSTALL ?= install

bindir = /usr/bin
libexecdir = /usr/lib/blue-yeti-autoreset
systemdunitdir = /usr/lib/systemd/system
systemduserunitdir = /usr/lib/systemd/user
udevrulesdir = /usr/lib/udev/rules.d
docdir = /usr/share/doc/blue-yeti-autoreset
licensedir = /usr/share/licenses/blue-yeti-autoreset

CPPFLAGS += $(shell $(PKG_CONFIG) --cflags libusb-1.0)
CFLAGS ?= -O2
CFLAGS += -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow -Wformat=2 -Werror
LDLIBS += $(shell $(PKG_CONFIG) --libs libusb-1.0)

.PHONY: all check clean install uninstall

all: build/blue-yeti-reset

build:
	mkdir -p build

build/blue-yeti-reset: src/blue-yeti-reset.c | build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $< $(LDLIBS) -o $@

check: build/blue-yeti-reset
	./build/blue-yeti-reset >/dev/null
	sh -n scripts/blue-yeti-autoreset tests/check-autoreset.sh
	python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' obs/blue-yeti-obs-reconnect
	sh ./tests/check-autoreset.sh
	# Verify the installed layout without requiring a host installation.
	+@set -eu; \
	check_root=$$(mktemp -d); \
	trap 'rm -r -- "$$check_root"' EXIT HUP INT TERM; \
	$(MAKE) DESTDIR="$$check_root" install; \
	systemd-analyze verify --root="$$check_root" --recursive-errors=no \
		"$(systemdunitdir)/blue-yeti-autoreset.service" \
		"$(systemdunitdir)/blue-yeti-autoreset-resume.service" \
		"$(systemdunitdir)/blue-yeti-autoreset-hotplug.service"; \
	if udevadm verify --help >/dev/null 2>&1; then \
		udevadm verify --no-style "$$check_root$(udevrulesdir)/60-blue-yeti-autoreset.rules"; \
	fi

install: build/blue-yeti-reset
	$(INSTALL) -D -m 0755 build/blue-yeti-reset \
		"$(DESTDIR)$(bindir)/blue-yeti-reset"
	$(INSTALL) -D -m 0755 scripts/blue-yeti-autoreset \
		"$(DESTDIR)$(libexecdir)/blue-yeti-autoreset"
	$(INSTALL) -D -m 0644 systemd/blue-yeti-autoreset.service \
		"$(DESTDIR)$(systemdunitdir)/blue-yeti-autoreset.service"
	$(INSTALL) -D -m 0644 systemd/blue-yeti-autoreset-resume.service \
		"$(DESTDIR)$(systemdunitdir)/blue-yeti-autoreset-resume.service"
	$(INSTALL) -D -m 0644 systemd/blue-yeti-autoreset-hotplug.service \
		"$(DESTDIR)$(systemdunitdir)/blue-yeti-autoreset-hotplug.service"
	$(INSTALL) -D -m 0644 udev/60-blue-yeti-autoreset.rules \
		"$(DESTDIR)$(udevrulesdir)/60-blue-yeti-autoreset.rules"
	$(INSTALL) -D -m 0755 obs/blue-yeti-obs-reconnect \
		"$(DESTDIR)$(bindir)/blue-yeti-obs-reconnect"
	$(INSTALL) -D -m 0644 obs/blue-yeti-obs-reconnect.service \
		"$(DESTDIR)$(systemduserunitdir)/blue-yeti-obs-reconnect.service"
	$(INSTALL) -D -m 0644 README.md "$(DESTDIR)$(docdir)/README.md"
	$(INSTALL) -D -m 0644 LICENSE "$(DESTDIR)$(licensedir)/LICENSE"

uninstall:
	rm -f "$(DESTDIR)$(bindir)/blue-yeti-reset"
	rm -f "$(DESTDIR)$(libexecdir)/blue-yeti-autoreset"
	rm -f "$(DESTDIR)$(systemdunitdir)/blue-yeti-autoreset.service"
	rm -f "$(DESTDIR)$(systemdunitdir)/blue-yeti-autoreset-resume.service"
	rm -f "$(DESTDIR)$(systemdunitdir)/blue-yeti-autoreset-hotplug.service"
	rm -f "$(DESTDIR)$(udevrulesdir)/60-blue-yeti-autoreset.rules"
	rm -f "$(DESTDIR)$(bindir)/blue-yeti-obs-reconnect"
	rm -f "$(DESTDIR)$(systemduserunitdir)/blue-yeti-obs-reconnect.service"
	rm -f "$(DESTDIR)$(docdir)/README.md"
	rm -f "$(DESTDIR)$(licensedir)/LICENSE"
	-rmdir "$(DESTDIR)$(libexecdir)" "$(DESTDIR)$(docdir)" "$(DESTDIR)$(licensedir)" 2>/dev/null

clean:
	rm -rf build
