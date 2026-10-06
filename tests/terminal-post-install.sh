#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=$(command -v python3)
POST_INSTALL="$PROJECT_DIR/features/terminal/post_install.py"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

directory=$(mktemp -d "$TMP_ROOT/case.XXXXXX")
mkdir -p "$directory/bin"
cat >"$directory/bin/xonsh" <<'EOF'
#!/bin/sh
printf '%s\n' "$FAKE_PYTHON"
EOF
cat >"$directory/bin/python" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$PIP_LOG"
EOF
chmod +x "$directory/bin/xonsh" "$directory/bin/python"

cat >"$directory/expected" <<EOF
-m
pip
install
--disable-pip-version-check
--upgrade
--target
$directory/.local/share/kaizen/xonsh-site
xontrib-sh==0.3.2
EOF

HOME="$directory" \
	PATH="$directory/bin:/usr/bin:/bin" \
	FAKE_PYTHON="$directory/bin/python" \
	PIP_LOG="$directory/actual" \
	"$PYTHON" "$POST_INSTALL" macos sync

diff -u "$directory/expected" "$directory/actual"

printf 'terminal post-install tests passed\n'
