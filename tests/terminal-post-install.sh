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
