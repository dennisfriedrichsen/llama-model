# llama-model

A small wrapper and configuration for running llama models on FreeBSD. It gives
local GGUF models short names and adds the correct multimodal projector
automatically, using POSIX shell without FreeBSD-specific shell features.

## Recommended layout

Keep the downloaded files wherever you store large model data. The wrapper
creates this short, stable catalog with symbolic links, rooted by default at
`/var/db/llama-model/catalog` (see [Defaults](#defaults) below):

```text
/var/db/llama-model/catalog/
├── server.args
├── llama-3.1-8b/
│   └── model.gguf -> /path/to/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf
└── qwen-vl/
    ├── model.gguf  -> /path/to/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf
    ├── mmproj.gguf -> /path/to/mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf
    └── server.args
```

This follows llama.cpp's convention of grouping a multimodal model and a file
whose name starts with `mmproj` in the same directory. The links mean a model
can retain its descriptive download name while commands use a memorable alias.

## Defaults

- **`llama-server`** is resolved through `PATH`, like any other command — on
  FreeBSD that's normally `/usr/local/bin/llama-server`, installed by the
  `misc/llama-cpp` package or port. Set `LLAMA_SERVER` (env var or in
  `llama-models.conf`) to an explicit path to pin a specific build instead.
- **The model catalog** defaults to the fixed system path
  `/var/db/llama-model/catalog` — it does not depend on `$HOME`. Set
  `LLAMA_MODEL_ROOT` to use a different directory (e.g. a personal catalog).
  `llama-model add` creates the directory (and its parents) the first time
  it's needed; read-only commands (`list`, `show`, `status`) never create it.

A system administrator typically needs to create `/var/db/llama-model` once
and grant the account that runs `llama-model` write access to it, e.g.:

```sh
install -d -o SERVICE_USER /var/db/llama-model/catalog
```

`llama-model` never runs `sudo` or changes ownership itself; if it can't
write to the configured catalog directory it reports that directory's path
in the error so you know what to fix.

### Migrating from `~/models/catalog`

Older versions defaulted the catalog to `~/models/catalog` and `llama-server`
to a build path under `$HOME`. Neither default depends on `$HOME` anymore,
but nothing is moved automatically:

- To keep using your existing per-user catalog unchanged, set
  `LLAMA_MODEL_ROOT=~/models/catalog` in `~/.config/llama-models.conf` (or
  the environment).
- To adopt the new system catalog, create it and copy your aliases in
  (`cp -R` preserves the symlinks; the underlying downloaded files are
  untouched either way):

  ```sh
  install -d -o SERVICE_USER /var/db/llama-model/catalog
  cp -R ~/models/catalog/. /var/db/llama-model/catalog/
  ```

## Install

Install it for your user (add `~/bin` to `PATH` if it is not already there),
or run as root for a system-wide install to `/usr/local` instead:

```sh
make install
```

This installs `llama-model` to `~/bin` and its man page to `~/man/man1` when
run as your user, or to `/usr/local/bin` and `/usr/local/man/man1` when run
as root (override either with `PREFIX=...`). It also drops example config
files — `llama-models.conf` (pointed at a catalog under
`~/.local/share/llama-model/catalog` for a per-user install, or
`/var/db/llama-model/catalog` for a root install; override with
`CATALOG=...`) and that catalog's `server.args` — only if those files don't
already exist, so re-running `make install` to pick up script updates never
clobbers your edited config. Run `make uninstall` to remove the installed
script and man page (pass the same `PREFIX=...` you installed with, if any).

Once installed, run `man llama-model` for full command and configuration
reference.

Edit the two installed configuration files for your binary, storage, host,
port, context size, and hardware. Each `server.args` line is exactly one
argument; put an option and its value on separate lines. Blank lines and lines
starting with `#` are ignored.

## Add and run models

```sh
# Text-only model
llama-model add llama8 ~/models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf

# Vision-language model
llama-model add qwen-vl \
  ~/models/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf \
  ~/models/mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf

llama-model list
llama-model show qwen-vl
llama-model command qwen-vl
llama-model run qwen-vl
```

Arguments after the alias are passed through to `llama-server`. They come last,
so they are useful for an occasional override:

```sh
llama-model run llama8 --port 8081 --ctx-size 16384
```

Put model-specific settings in `$LLAMA_MODEL_ROOT/ALIAS/server.args`
(`/var/db/llama-model/catalog/ALIAS/server.args` by default).
For example, a model that needs flash attention disabled could contain:

```text
--flash-attn
off
```

The wrapper stays in the foreground and replaces itself with `llama-server`.
That makes signals and exit status behave correctly under `daemon(8)`, rc.d,
tmux, or another service manager.

## Updating a downloaded file

The catalog contains only symbolic links. To change a quantization or model
revision, atomically replace the appropriate link:

```sh
ln -sfn "$HOME/models/new-long-model-name.gguf" \
  /var/db/llama-model/catalog/llama8/model.gguf
```

Run `llama-model show llama8` afterward to verify the target before starting it.
