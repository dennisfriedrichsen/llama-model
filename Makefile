PREFIX ?= $(HOME)
BINDIR = $(PREFIX)/bin
CONFDIR = $(HOME)/.config
CATALOG = $(HOME)/models/catalog

.PHONY: install install-bin install-config uninstall check

install: install-bin install-config

install-bin:
	install -d $(BINDIR)
	ver=$$(cat VERSION); sed "s/^VERSION=dev\$$/VERSION=$$ver/" llama-model > $(BINDIR)/llama-model
	chmod 0755 $(BINDIR)/llama-model

install-config:
	install -d $(CONFDIR) $(CATALOG)
	[ -f $(CONFDIR)/llama-models.conf ] || install -m 0644 llama-models.conf.example $(CONFDIR)/llama-models.conf
	[ -f $(CATALOG)/server.args ] || install -m 0644 server.args.example $(CATALOG)/server.args

uninstall:
	rm -f $(BINDIR)/llama-model

check:
	sh -n llama-model
	command -v shellcheck >/dev/null 2>&1 && shellcheck llama-model || true
