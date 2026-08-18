# llama-model

A small wrapper and configuration for running llama models on FreeBSD. It gives
local GGUF models short names and adds the correct multimodal projector
automatically, using POSIX shell without FreeBSD-specific shell features.

## Recommended layout

Keep the downloaded files wherever you store large model data. The wrapper
creates this short, stable catalog with symbolic links:

```text
~/models/
├── Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf
├── Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf
├── mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf
└── catalog/
    ├── server.args
    ├── llama-3.1-8b/
    │   └── model.gguf -> ../../Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf
    └── qwen-vl/
        ├── model.gguf  -> ../../Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf
        ├── mmproj.gguf -> ../../mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf
        └── server.args
```

This follows llama.cpp's convention of grouping a multimodal model and a file
whose name starts with `mmproj` in the same directory. The links mean a model
can retain its descriptive download name while commands use a memorable alias.

## Install

Install it for your user (add `~/bin` to `PATH` if it is not already there):

```sh
make install
```

This installs `llama-model` to `~/bin` (override with `PREFIX=...`), and drops
the example config files into `~/.config/llama-models.conf` and
`~/models/catalog/server.args` only if those files don't already exist, so
re-running `make install` to pick up script updates never clobbers your
edited config. Run `make uninstall` to remove the installed script.

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

Put model-specific settings in `~/models/catalog/ALIAS/server.args`.
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
  "$HOME/models/catalog/llama8/model.gguf"
```

Run `llama-model show llama8` afterward to verify the target before starting it.
