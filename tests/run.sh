#!/bin/sh

# POSIX-sh test suite for llama-model's platform-default behavior: model
# directory resolution, llama-server resolution via PATH, directory
# creation/permission errors, and no dependence on $HOME. Never touches the
# real /var/db or /var/lib; everything runs against a per-test tmpdir.
#
# Run directly (sh tests/run.sh) or via 'make check'.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LLAMA_MODEL=$here/../llama-model

pass=0
fail=0

note() { printf '%s\n' "$*"; }

ok() {
    pass=$((pass + 1))
    note "ok - $1"
}

not_ok() {
    fail=$((fail + 1))
    note "not ok - $1"
    shift
    [ "$#" -eq 0 ] || printf '    %s\n' "$@"
}

# assert_status DESC EXPECTED_STATUS -- CMD...
# Runs CMD with output captured in $out, and status in $status.
run_case() {
    out=$("$@" 2>&1)
    status=$?
}

assert_status() {
    desc=$1
    want=$2
    shift 2
    run_case "$@"
    if [ "$status" -eq "$want" ]; then
        ok "$desc"
    else
        not_ok "$desc" "expected exit $want, got $status" "output: $out"
    fi
}

assert_contains() {
    desc=$1
    needle=$2
    haystack=$3
    case $haystack in
        *"$needle"*) ok "$desc" ;;
        *) not_ok "$desc" "expected output to contain: $needle" "got: $haystack" ;;
    esac
}

assert_not_contains() {
    desc=$1
    needle=$2
    haystack=$3
    case $haystack in
        *"$needle"*) not_ok "$desc" "expected output NOT to contain: $needle" "got: $haystack" ;;
        *) ok "$desc" ;;
    esac
}

# A fresh scratch directory per test run, cleaned up on exit. Everything a
# test needs (fake catalogs, fake PATH entries, fake $HOME) lives under it,
# never under the real /var/db or /var/lib.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/llama-model-tests.XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

make_stub_server() {
    # Writes an executable llama-server stub at $1 that just echoes a tag
    # and its arguments, so tests can tell which stub actually ran.
    dir=$(dirname "$1")
    mkdir -p "$dir"
    cat > "$1" <<EOF
#!/bin/sh
printf '%s %s\n' "$2" "\$*"
EOF
    chmod +x "$1"
}

make_dummy_gguf() {
    : > "$1"
}

# Common environment for every test: no config file, no PATH entries beyond
# what the test explicitly adds, and a decoy \$HOME so any accidental
# HOME-dependence shows up.
base_env() {
    LLAMA_MODEL_CONFIG=/dev/null
    export LLAMA_MODEL_CONFIG
    unset LLAMA_SERVER LLAMA_MODEL_ROOT LLAMA_GLOBAL_ARGS 2>/dev/null || true
}

# --- explicit LLAMA_MODEL_ROOT override --------------------------------
test_explicit_model_root_override() {
    base_env
    root="$WORK/explicit-root"
    model="$WORK/explicit-root-model.gguf"
    make_dummy_gguf "$model"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    assert_status "explicit LLAMA_MODEL_ROOT: add succeeds" 0 \
        "$LLAMA_MODEL" add expl "$model"
    out=$("$LLAMA_MODEL" list)
    assert_contains "explicit LLAMA_MODEL_ROOT: alias appears under override" "expl" "$out"
    [ -f "$root/expl/model.gguf" ] && ok "explicit LLAMA_MODEL_ROOT: catalog created at override path" \
        || not_ok "explicit LLAMA_MODEL_ROOT: catalog created at override path" "missing $root/expl/model.gguf"
    unset LLAMA_MODEL_ROOT
}

# --- no dependence on $HOME ---------------------------------------------
test_default_model_root_ignores_home() {
    base_env
    decoy_home="$WORK/decoy-home"
    decoy_model="$decoy_home/models/catalog/decoy/model.gguf"
    mkdir -p "$(dirname "$decoy_model")"
    make_dummy_gguf "$decoy_model"

    # Old versions defaulted LLAMA_MODEL_ROOT to $HOME/models/catalog; with
    # a decoy alias planted there and HOME pointed at the decoy, the
    # default must not surface it (it must not depend on $HOME at all).
    assert_status "default model root: list is read-only and does not error when default dir is absent" 0 \
        env HOME="$decoy_home" "$LLAMA_MODEL" list
    assert_not_contains "default model root: ignores \$HOME/models/catalog decoy" "decoy" "$out"
}

# --- read-only op does not create the model directory -------------------
test_readonly_does_not_create_dir() {
    base_env
    root="$WORK/readonly-root/models"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    assert_status "read-only op: list succeeds when model dir is absent" 0 \
        "$LLAMA_MODEL" list
    [ ! -e "$root" ] && ok "read-only op: list does not create the model dir" \
        || not_ok "read-only op: list does not create the model dir" "found $root"
    unset LLAMA_MODEL_ROOT
}

# --- write op creates the model directory --------------------------------
test_write_op_creates_dir() {
    base_env
    root="$WORK/write-root/nested/models"
    model="$WORK/write-root-model.gguf"
    make_dummy_gguf "$model"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    assert_status "write op: add creates missing model dir (and parents)" 0 \
        "$LLAMA_MODEL" add w1 "$model"
    [ -d "$root/w1" ] && ok "write op: alias directory exists after add" \
        || not_ok "write op: alias directory exists after add" "missing $root/w1"
    unset LLAMA_MODEL_ROOT
}

# --- permission failure gives an actionable error ------------------------
test_permission_failure() {
    if [ "$(id -u)" -eq 0 ]; then
        note "skip - permission failure test (running as root, permissions unenforced)"
        return
    fi
    base_env
    parent="$WORK/readonly-parent"
    mkdir -p "$parent"
    chmod 555 "$parent"
    root="$parent/models"
    model="$WORK/perm-model.gguf"
    make_dummy_gguf "$model"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    assert_status "permission failure: add fails when model dir can't be created" 1 \
        "$LLAMA_MODEL" add p1 "$model"
    assert_contains "permission failure: error names the target directory" "$root" "$out"
    chmod 755 "$parent"
    unset LLAMA_MODEL_ROOT
}

# --- paths containing spaces ----------------------------------------------
test_paths_with_spaces() {
    base_env
    root="$WORK/spacey dir/models"
    model="$WORK/spacey dir/My Model File.gguf"
    mkdir -p "$(dirname "$model")"
    make_dummy_gguf "$model"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    assert_status "spaces: add succeeds with spaces in root and model path" 0 \
        "$LLAMA_MODEL" add sp "$model"
    out=$("$LLAMA_MODEL" show sp)
    assert_contains "spaces: show resolves the spacey model path" "My Model File.gguf" "$out"
    unset LLAMA_MODEL_ROOT
}

# --- default llama-server resolution through PATH -------------------------
test_default_server_via_path() {
    base_env
    root="$WORK/path-root"
    model="$WORK/path-model.gguf"
    make_dummy_gguf "$model"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    "$LLAMA_MODEL" add ps "$model" >/dev/null

    bindir="$WORK/path-bin"
    make_stub_server "$bindir/llama-server" STUB-PATH

    out=$(PATH="$bindir:$PATH" "$LLAMA_MODEL" run ps 2>&1)
    status=$?
    assert_status "default server: run resolves llama-server via PATH" 0 \
        env PATH="$bindir:$PATH" "$LLAMA_MODEL" run ps
    assert_contains "default server: PATH-resolved stub actually ran" "STUB-PATH" "$out"
    unset LLAMA_MODEL_ROOT
}

# --- missing llama-server gives an actionable error ------------------------
test_missing_server() {
    base_env
    root="$WORK/missing-root"
    model="$WORK/missing-model.gguf"
    make_dummy_gguf "$model"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    "$LLAMA_MODEL" add ms "$model" >/dev/null

    empty_path="$WORK/empty-path-bin"
    mkdir -p "$empty_path"
    out=$(PATH="$empty_path" "$LLAMA_MODEL" run ms 2>&1)
    status=$?
    assert_status "missing server: run fails when llama-server is not on PATH" 1 \
        env PATH="$empty_path" "$LLAMA_MODEL" run ms
    assert_contains "missing server: error is actionable (mentions PATH or LLAMA_SERVER)" "LLAMA_SERVER" "$out"
    unset LLAMA_MODEL_ROOT
}

# --- explicit executable override takes precedence over PATH --------------
test_explicit_server_override_wins() {
    base_env
    root="$WORK/override-root"
    model="$WORK/override-model.gguf"
    make_dummy_gguf "$model"
    LLAMA_MODEL_ROOT=$root
    export LLAMA_MODEL_ROOT
    "$LLAMA_MODEL" add ov "$model" >/dev/null

    bindir="$WORK/override-bin"
    make_stub_server "$bindir/llama-server" STUB-PATH
    make_stub_server "$WORK/explicit-server" STUB-EXPLICIT

    out=$(PATH="$bindir:$PATH" LLAMA_SERVER="$WORK/explicit-server" "$LLAMA_MODEL" run ov 2>&1)
    assert_contains "explicit override: explicit LLAMA_SERVER wins over PATH" "STUB-EXPLICIT" "$out"
    assert_not_contains "explicit override: PATH stub is not the one that ran" "STUB-PATH" "$out"
    unset LLAMA_MODEL_ROOT
}

test_explicit_model_root_override
test_default_model_root_ignores_home
test_readonly_does_not_create_dir
test_write_op_creates_dir
test_permission_failure
test_paths_with_spaces
test_default_server_via_path
test_missing_server
test_explicit_server_override_wins

note ""
note "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
