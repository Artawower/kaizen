#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=$(command -v python3)
POST_INSTALL="$PROJECT_DIR/features/terminal/post_install.py"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

run_case() {
	local virtual_environment=$1
	shift
	local directory
	directory=$(mktemp -d "$TMP_ROOT/case.XXXXXX")
	mkdir -p "$directory/bin"
	cat >"$directory/bin/xonsh" <<'EOF'
#!/bin/sh
printf '%s\n' "$FAKE_PYTHON" "$FAKE_VIRTUAL_ENVIRONMENT"
EOF
	cat >"$directory/bin/python" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$PIP_LOG"
EOF
	chmod +x "$directory/bin/xonsh" "$directory/bin/python"
	printf '%s\n' "$@" >"$directory/expected"
	PATH="$directory/bin:/usr/bin:/bin" \
		FAKE_PYTHON="$directory/bin/python" \
		FAKE_VIRTUAL_ENVIRONMENT="$virtual_environment" \
		PIP_LOG="$directory/actual" \
		"$PYTHON" "$POST_INSTALL" macos sync
	diff -u "$directory/expected" "$directory/actual"
}

run_case True \
	-m pip install \
	--disable-pip-version-check \
	xontrib-sh==0.3.2

run_case False \
	-m pip install \
	--user \
	--break-system-packages \
	--disable-pip-version-check \
	xontrib-sh==0.3.2

printf 'terminal post-install tests passed\n'
