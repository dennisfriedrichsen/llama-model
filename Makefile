# Root (or sudo) installs system-wide to /usr/local by default; everyone
# else installs per-user to ~/.local. Pass PREFIX=... explicitly to override
# either default.
.if !defined(PREFIX)
PREFIX != if [ "`id -u`" = 0 ]; then echo /usr/local; else echo ${HOME}/.local; fi
.endif
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/man/man1
CONFDIR = $(HOME)/.config
CATALOG = $(HOME)/models/catalog

.PHONY: install install-bin install-man install-config uninstall check

install: install-bin install-man install-config

install-bin:
	install -d $(BINDIR)
	ver=$$(cat VERSION); sed "s/^VERSION=dev\$$/VERSION=$$ver/" llama-model > $(BINDIR)/llama-model
	chmod 0755 $(BINDIR)/llama-model

install-man:
	install -d $(MANDIR)
	install -m 0644 llama-model.1 $(MANDIR)/llama-model.1

install-config:
	install -d $(CONFDIR) $(CATALOG)
	[ -f $(CONFDIR)/llama-models.conf ] || install -m 0644 llama-models.conf.example $(CONFDIR)/llama-models.conf
	[ -f $(CATALOG)/server.args ] || install -m 0644 server.args.example $(CATALOG)/server.args

uninstall:
	rm -f $(BINDIR)/llama-model $(MANDIR)/llama-model.1

check:
	sh -n llama-model
	command -v shellcheck >/dev/null 2>&1 && shellcheck llama-model || true
	command -v mandoc >/dev/null 2>&1 && mandoc -Tlint llama-model.1 || true
