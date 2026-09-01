#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=$(command -v python3)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

assert_contains() {
	[[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"
}

assert_not_contains() {
	[[ "$1" != *"$2"* ]] || fail "expected output not to contain: $2"
}

assert_file() {
	[[ -f "$1" ]] || fail "expected file: $1"
}

assert_no_file() {
	[[ ! -e "$1" ]] || fail "expected no file: $1"
}

new_scenario() {
	SCENARIO_DIR=$(mktemp -d "$TMP_ROOT/scenario.XXXXXX")
	HOME_DIR="$SCENARIO_DIR/home"
	SOURCE_DIR="$SCENARIO_DIR/source"
	EDITOR_FILE="$SCENARIO_DIR/editor"
	EDITOR_MARKER="$SCENARIO_DIR/editor-ran"
	SYNC_MARKER="$SCENARIO_DIR/sync-ran"
	mkdir -p "$HOME_DIR" "$SOURCE_DIR"
	cat >"$SOURCE_DIR/config.example.toml" <<'EOF'
email = "you@example.com"
full_name = "Your Name"
EOF
	cat >"$SOURCE_DIR/kaizen.py" <<'EOF'
import os, pathlib, sys
pathlib.Path(os.environ["SYNC_MARKER"]).write_text(" ".join(sys.argv[1:]))
EOF
	cat >"$EDITOR_FILE" <<'EOF'
#!/bin/sh
[ "$1" = "--wait" ] || exit 2
file=$2
"$KAIZEN_PYTHON" -c 'import pathlib, sys; path = pathlib.Path(sys.argv[1]); text = path.read_text().replace("you@example.com", sys.argv[2]).replace("Your Name", sys.argv[3]); path.write_text(text)' "$file" "$EDITOR_EMAIL" "$EDITOR_NAME"
touch "$EDITOR_MARKER"
EOF
	chmod +x "$EDITOR_FILE"
}

run_in_pty() {
	local input=$1
	shift
	PTY_INPUT=$input "$PYTHON" - "$@" <<'PY'
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvpe(sys.argv[1], sys.argv[1:], os.environ)
os.write(fd, os.environ["PTY_INPUT"].encode())
output = bytearray()
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    output.extend(chunk)
_, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(output)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
}

run_without_tty() {
	"$PYTHON" - "$@" <<'PY'
import subprocess, sys
completed = subprocess.run(sys.argv[1:], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
sys.stdout.buffer.write(completed.stdout)
raise SystemExit(completed.returncode)
PY
}

run_installer_in_pty() {
	local input=$1
	shift
	run_in_pty "$input" env \
		HOME="$HOME_DIR" \
		KAIZEN_SOURCE_DIR="$SOURCE_DIR" \
		KAIZEN_PYTHON="$PYTHON" \
		SYNC_MARKER="$SYNC_MARKER" \
		EDITOR_MARKER="$EDITOR_MARKER" \
		"$@" \
		sh "$PROJECT_DIR/install.sh"
}

run_installer_without_tty() {
	run_without_tty env \
		HOME="$HOME_DIR" \
		KAIZEN_SOURCE_DIR="$SOURCE_DIR" \
		KAIZEN_PYTHON="$PYTHON" \
		SYNC_MARKER="$SYNC_MARKER" \
		EDITOR_MARKER="$EDITOR_MARKER" \
		"$@" \
		sh "$PROJECT_DIR/install.sh"
}

test_full_name_placeholder_blocks_sync() {
	new_scenario
	output=$(run_installer_in_pty $'y\n' \
		VISUAL="$EDITOR_FILE --wait" \
		EDITOR_EMAIL="person@example.com" \
		EDITOR_NAME="Your Name")
	assert_file "$EDITOR_MARKER"
	assert_no_file "$SYNC_MARKER"
	assert_contains "$output" "config still has placeholder values"
}

test_email_placeholder_blocks_sync() {
	new_scenario
	output=$(run_installer_in_pty $'y\n' \
		VISUAL="$EDITOR_FILE --wait" \
		EDITOR_EMAIL="you@example.com" \
		EDITOR_NAME="Example Person")
	assert_no_file "$SYNC_MARKER"
	assert_contains "$output" "config still has placeholder values"
}

test_yes_runs_sync() {
	new_scenario
	output=$(run_installer_in_pty $'yes\n' \
		VISUAL="$EDITOR_FILE --wait" \
		EDITOR_EMAIL="person@example.com" \
		EDITOR_NAME="Example Person")
	assert_file "$SYNC_MARKER"
	[[ $(cat "$SYNC_MARKER") == "sync" ]] || fail "expected sync command"
	assert_contains "$output" "running kaizen sync"
}

test_no_defers_sync() {
	new_scenario
	output=$(run_installer_in_pty $'n\n' \
		VISUAL="$EDITOR_FILE --wait" \
		EDITOR_EMAIL="person@example.com" \
		EDITOR_NAME="Example Person")
	assert_no_file "$SYNC_MARKER"
	assert_contains "$output" "run when ready:"
	assert_not_contains "$output" "edit $HOME_DIR/.config/kaizen/config.toml"
}

test_editor_failure_warns() {
	new_scenario
	output=$(run_installer_in_pty $'n\n' VISUAL=false)
	assert_no_file "$SYNC_MARKER"
	assert_contains "$output" "warning: could not open false"
}

test_no_tty_skips_editor() {
	new_scenario
	output=$(run_installer_without_tty \
		VISUAL="$EDITOR_FILE --wait" \
		EDITOR_EMAIL="person@example.com" \
		EDITOR_NAME="Example Person")
	assert_no_file "$EDITOR_MARKER"
	assert_contains "$output" "edit $HOME_DIR/.config/kaizen/config.toml"
}

test_existing_config_is_untouched() {
	new_scenario
	mkdir -p "$HOME_DIR/.config/kaizen"
	printf 'email = "saved@example.com"\nfull_name = "Saved Name"\n' >"$HOME_DIR/.config/kaizen/config.toml"
	before=$(cat "$HOME_DIR/.config/kaizen/config.toml")
	output=$(run_installer_without_tty VISUAL=false)
	after=$(cat "$HOME_DIR/.config/kaizen/config.toml")
	[[ "$before" == "$after" ]] || fail "existing config changed"
	assert_contains "$output" "run when ready:"
}

test_full_name_placeholder_blocks_sync
test_email_placeholder_blocks_sync
test_yes_runs_sync
test_no_defers_sync
test_editor_failure_warns
test_no_tty_skips_editor
test_existing_config_is_untouched
printf 'installer tests passed\n'
