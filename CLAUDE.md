# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single POSIX `sh` script (`llama-model`) that wraps `llama.cpp`'s `llama-server`. It gives
local GGUF model files short, stable aliases and assembles the right `llama-server` invocation
(model path, mmproj path, and layered argument files) for each alias. There is no build step,
package manifest, or test suite — the entire implementation is the `llama-model` file itself.

Written in strict POSIX shell (no bashisms) because it targets FreeBSD, where `/bin/sh` is not
bash. Do not introduce bash-only syntax (`[[ ]]`, arrays, `local`, `source`, process substitution).

## Running / trying changes

There's no test suite, so validate changes by exercising the script directly:

```sh
# Sanity-check syntax (POSIX sh, not bash)
sh -n llama-model

# Exercise commands against a scratch catalog
LLAMA_MODEL_ROOT=/tmp/catalog ./llama-model add test-alias /path/to/some.gguf
LLAMA_MODEL_ROOT=/tmp/catalog ./llama-model list
LLAMA_MODEL_ROOT=/tmp/catalog ./llama-model show test-alias
LLAMA_MODEL_ROOT=/tmp/catalog ./llama-model command test-alias   # prints the resolved command, doesn't exec
```

`command` is the fast way to check argument assembly without needing a real `llama-server`
binary or a real GGUF file present.

If `shellcheck` is available locally, run it against `llama-model` before committing — the repo
doesn't currently invoke it in CI, but the script is meant to stay shellcheck-clean POSIX sh.

## Architecture

Everything lives in one script, organized as: config loading → helper functions → command dispatch
(`list`, `show`, `add`, `run`, `command`).

**Configuration is layered and sourced from shell files, not parsed:**
1. `~/.config/llama-models.conf` (or `$LLAMA_MODELS_CONFIG`) is `.`-sourced if present, and may set
   `LLAMA_SERVER`, `LLAMA_MODEL_ROOT`, `LLAMA_GLOBAL_ARGS`.
2. Anything unset falls back to hardcoded defaults (`~/src/github/ggml-org/llama.cpp/build/bin/llama-server`,
   `~/models/catalog`).

**The catalog (`$LLAMA_MODEL_ROOT`) is the on-disk data model**, not a database or JSON file:
- Each alias is a directory `$LLAMA_MODEL_ROOT/ALIAS/` containing a symlink `model.gguf` (and
  optionally `mmproj.gguf` for vision models) pointing at the real, long-named downloaded file.
- `add` just creates the directory and symlinks; it never copies model data.
- `show`/`list` read this directory structure directly — there's no separate index to keep in sync.
- Swapping a model's underlying file/quantization means re-pointing the symlink
  (`ln -sfn newfile … catalog/ALIAS/model.gguf`), not editing the script or a config entry.

**Argument assembly (`prepare_command`) is a merge of three sources, in this precedence order
(later wins, since they're appended in reverse and `llama-server` uses last-flag-wins semantics)**:
1. `$LLAMA_GLOBAL_ARGS` file (default `$LLAMA_MODEL_ROOT/server.args`) — options for every model.
2. `$LLAMA_MODEL_ROOT/ALIAS/server.args` — per-model overrides.
3. Extra CLI args passed after the alias on `run`/`command` — highest precedence, appended last.

Args files use **one argument per line** (an option and its value are two separate lines), with
blank lines and `#`-comments skipped. This format is why `read_args` splits on newline via a
temporary `IFS` change rather than word-splitting — it's what lets argument values contain spaces.

**`run` vs `command`**: both build the identical argument list via `prepare_command`. `run` does
`exec "$LLAMA_SERVER" "$@"` — the wrapper replaces itself in-place so signals/exit status pass
through correctly under `daemon(8)`, rc.d, or tmux. `command` instead shell-quotes and prints the
equivalent invocation (via `quote_arg`) without executing anything, useful for copy-pasting or
debugging what would run.

**Alias validation** (`check_alias`) restricts aliases to `[A-Za-z0-9._-]` — this is what's safe to
use as a single path component under `$LLAMA_MODEL_ROOT`.
