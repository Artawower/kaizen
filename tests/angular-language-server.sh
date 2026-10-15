#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
WRAPPER="$PROJECT_DIR/dotfiles/dot_config/bin/executable_angular-language-server"
NODE=$(command -v node)
TMP_ROOT=$(mktemp -d)
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
trap 'rm -rf "$TMP_ROOT"' EXIT

run_case() {
    local mode=$1
    local entrypoint=$2
    local directory="$TMP_ROOT/$mode-$entrypoint with spaces"
    local prefix="$directory/install"
    local server_root="$prefix/store/angular/node_modules/@angular/language-server"
    local native_bin="$prefix/node_modules/.bin"
    mkdir -p "$directory/bin" "$directory/workspace" "$native_bin" \
        "$prefix/node_modules/@angular" "$server_root/bin"
    ln -s "$NODE" "$directory/bin/node"
    ln -s "$server_root" "$prefix/node_modules/@angular/language-server"
    printf '%s\n' '{"name":"@angular/language-server","version":"22.2.1"}' >"$server_root/package.json"

    cat >"$server_root/bin/ngserver" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$NGSERVER_LOG"
EOF
    chmod +x "$server_root/bin/ngserver"

    if [ "$entrypoint" = symlink ]; then
        ln -s "$server_root/bin/ngserver" "$native_bin/ngserver"
    else
        cat >"$native_bin/ngserver" <<'EOF'
#!/bin/sh
exec "$SERVER_ROOT/bin/ngserver" "$@"
EOF
        chmod +x "$native_bin/ngserver"
    fi

    if [ "$mode" != unmanaged ]; then
        cat >"$directory/bin/mise" <<'EOF'
#!/bin/sh
if [ "$*" = 'which ngserver' ] && [ "$MISE_MODE" = managed ]; then
    printf '%s\n' "$MANAGED_NGSERVER"
    exit 0
fi
exit 91
EOF
        chmod +x "$directory/bin/mise"
    fi

    local test_path="$directory/bin:/usr/bin:/bin"
    if [ "$mode" = managed ]; then
        ln -s "$directory/bin/mise" "$directory/bin/ngserver"
    else
        test_path="$native_bin:$test_path"
    fi

    (
        cd "$directory/workspace"
        PATH="$test_path" \
            MISE_MODE="$mode" \
            MANAGED_NGSERVER="$native_bin/ngserver" \
            SERVER_ROOT="$server_root" \
            NGSERVER_LOG="$directory/actual" \
            /bin/bash "$WRAPPER" --stdio --logFile "$directory/server log"
    )

    printf '%s\n' --stdio --logFile "$directory/server log" \
        --tsProbeLocations "$directory/workspace/node_modules,$server_root" \
        --ngProbeLocations "$directory/workspace/node_modules,$server_root" >"$directory/expected"
    diff -u "$directory/expected" "$directory/actual"
    printf 'passed: %s / %s\n' "$mode" "$entrypoint"
}

for mode in managed unmanaged fallback; do
    for entrypoint in shim symlink; do
        run_case "$mode" "$entrypoint"
    done
done

mkdir -p "$TMP_ROOT/missing"
if PATH="$TMP_ROOT/missing:/usr/bin:/bin" /bin/bash "$WRAPPER" >"$TMP_ROOT/missing-output" 2>&1; then
    printf 'wrapper accepted a missing ngserver\n' >&2
    exit 1
fi

printf 'Angular language server wrapper tests passed\n'
