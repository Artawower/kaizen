#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=$(python3 -c 'import sys; print(sys.executable)')
POST_INSTALL="$PROJECT_DIR/features/hooks/terminal/post_install.py"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

directory=$(mktemp -d "$TMP_ROOT/case.XXXXXX")
mkdir -p "$directory/bin"

cat >"$directory/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$HERDR_LOG"
if [ "$1" != plugin ] || [ "$2" != install ] || [ "$3" != crierr/herdr-tmux-layout ] || [ "$4" != -y ]; then
    exit 2
fi
exit "${HERDR_EXIT:-0}"
EOF
chmod +x "$directory/bin/herdr"

HOME="$directory" \
	PATH="$directory/bin:/usr/bin:/bin" \
	FAKE_PYTHON="$directory/bin/python" \
	PIP_LOG="$directory/actual" \
	HERDR_LOG="$directory/herdr-actual" \
	"$PYTHON" "$POST_INSTALL" macos update

printf '%s\n' plugin install crierr/herdr-tmux-layout -y >"$directory/herdr-expected"
diff -u "$directory/herdr-expected" "$directory/herdr-actual"

if HOME="$directory" \
	PATH="$directory/bin:/usr/bin:/bin" \
	FAKE_PYTHON="$directory/bin/python" \
	PIP_LOG="$directory/actual" \
	HERDR_LOG="$directory/herdr-actual" \
	HERDR_EXIT=7 \
	"$PYTHON" "$POST_INSTALL" macos update >"$directory/failure" 2>&1; then
    printf 'terminal post-install ignored a failed plugin installation\n' >&2
    exit 1
fi

printf 'terminal post-install tests passed\n'
