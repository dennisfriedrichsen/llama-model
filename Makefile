# Root (or sudo) installs system-wide to /usr/local by default; everyone
# else installs per-user to $HOME. Pass PREFIX=... explicitly to override
# either default.
.if !defined(PREFIX)
PREFIX != if [ "`id -u`" = 0 ]; then echo /usr/local; else echo ${HOME}; fi
.endif
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/man/man1
CONFDIR = $(HOME)/.config

# Root installs share llama-model's own system default
# (/var/db/llama-model/catalog); everyone else gets a per-user catalog under
# their XDG data directory, since /var/db is typically not user-writable.
# Pass CATALOG=... explicitly to override either default.
.if !defined(CATALOG)
CATALOG != if [ "`id -u`" = 0 ]; then echo /var/db/llama-model/catalog; else echo $(HOME)/.local/share/llama-model/catalog; fi
.endif

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
	install -d $(CONFDIR)
	[ -f $(CONFDIR)/llama-model.conf ] || { \
		sed "s|/var/db/llama-model/catalog|$(CATALOG)|" llama-model.conf.example > $(CONFDIR)/llama-model.conf; \
		chmod 0644 $(CONFDIR)/llama-model.conf; \
	}
	install -d $(CATALOG)
	[ -f $(CATALOG)/server.args ] || install -m 0644 server.args.example $(CATALOG)/server.args

uninstall:
	rm -f $(BINDIR)/llama-model $(MANDIR)/llama-model.1

check:
	sh -n llama-model
	command -v shellcheck >/dev/null 2>&1 && shellcheck llama-model || true
	command -v mandoc >/dev/null 2>&1 && mandoc -Tlint llama-model.1 || true
	sh tests/run.sh
