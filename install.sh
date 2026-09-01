#!/bin/sh
set -eu

REPO="${KAIZEN_REPO:-https://github.com/artawower/kaizen.git}"
REF="${KAIZEN_REF:-master}"
INSTALL_DIR="${KAIZEN_DIR:-$HOME/.local/share/kaizen}"
SOURCE_DIR="${KAIZEN_SOURCE_DIR:-}"
INSTALL_MODE="managed"
CONFIG_DIR="$HOME/.config/kaizen"
CONFIG_FILE="$CONFIG_DIR/config.toml"
BIN_DIR="$HOME/.local/bin"
RUNTIME_DIR="${KAIZEN_RUNTIME_DIR:-$HOME/.local/share/kaizen-runtime}"
PYTHON_VERSION="${KAIZEN_PYTHON_VERSION:-3.12}"
PYTHON="${KAIZEN_PYTHON:-$(command -v python3 || true)}"
UV="${KAIZEN_UV:-$RUNTIME_DIR/bin/uv}"
EMAIL_PLACEHOLDER="you@example.com"
FULL_NAME_PLACEHOLDER="Your Name"

say() { printf '%s\n' "$*" >&2; }
die() {
	say "error: $*"
	exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "missing: $1"; }

config_has_placeholders() {
	grep -Fq "$EMAIL_PLACEHOLDER" "$CONFIG_FILE" ||
		grep -Fq "$FULL_NAME_PLACEHOLDER" "$CONFIG_FILE"
}

open_config() {
	editor="${VISUAL:-${EDITOR:-vi}}"
	say "opening $CONFIG_FILE in $editor — set your email and full_name"
	"$PYTHON" -c 'import os, shlex, sys; command = shlex.split(sys.argv[1]); command or sys.exit(127); os.execvp(command[0], [*command, sys.argv[2]])' \
		"$editor" "$CONFIG_FILE" </dev/tty >/dev/tty
}

offer_sync() {
	if config_has_placeholders; then
		say "config still has placeholder values"
		return
	fi
	printf 'run kaizen sync now? [y/N] ' >&2
	read -r answer </dev/tty || answer=""
	answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
	if [ "$answer" != "y" ] && [ "$answer" != "yes" ]; then
		return
	fi
	say "running kaizen sync"
	"$KAIZEN_COMMAND" sync
	exit 0
}

python_ok() {
	[ -n "$1" ] && "$1" -c "import sys,tomllib; assert sys.version_info >= (3,11)" 2>/dev/null
}

install_python() {
	if [ ! -x "$UV" ]; then
		need curl
		mkdir -p "$RUNTIME_DIR/bin"
		say "installing uv to $RUNTIME_DIR/bin"
		curl -LsSf https://astral.sh/uv/install.sh |
			UV_UNMANAGED_INSTALL="$RUNTIME_DIR/bin" sh
	fi
	mkdir -p "$RUNTIME_DIR/python"
	say "installing Python $PYTHON_VERSION to $RUNTIME_DIR/python"
	UV_PYTHON_INSTALL_DIR="$RUNTIME_DIR/python" \
		"$UV" python install "$PYTHON_VERSION" --no-bin
	PYTHON=$(UV_PYTHON_INSTALL_DIR="$RUNTIME_DIR/python" \
		"$UV" python find "$PYTHON_VERSION" --managed-python)
}

case "$(uname -s)" in
Darwin | Linux) ;;
*) die "unsupported OS: $(uname -s)" ;;
esac

if ! python_ok "$PYTHON"; then
	install_python
fi
python_ok "$PYTHON" || die "failed to install Python 3.11+"

if [ -n "$SOURCE_DIR" ]; then
	SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
	[ -f "$SOURCE_DIR/kaizen.py" ] || die "kaizen.py not found in $SOURCE_DIR"
	[ -f "$SOURCE_DIR/config.example.toml" ] || die "config.example.toml not found in $SOURCE_DIR"
	INSTALL_DIR="$SOURCE_DIR"
	INSTALL_MODE="development"
	say "using local kaizen source at $INSTALL_DIR"
else
	need git
	if [ -d "$INSTALL_DIR/.git" ]; then
		say "updating kaizen $REF at $INSTALL_DIR"
		git -C "$INSTALL_DIR" fetch --depth=1 origin "$REF"
		git -C "$INSTALL_DIR" checkout -B "$REF" FETCH_HEAD
	elif [ -e "$INSTALL_DIR" ]; then
		die "$INSTALL_DIR exists and is not a git checkout"
	else
		say "cloning kaizen $REF to $INSTALL_DIR"
		git clone --depth=1 --branch "$REF" "$REPO" "$INSTALL_DIR"
	fi
fi

mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
	cp "$INSTALL_DIR/config.example.toml" "$CONFIG_FILE"
	CONFIG_CREATED=1
	say "created $CONFIG_FILE — edit it to enable features"
fi

mkdir -p "$HOME/.config/chezmoi"
cat >"$HOME/.config/chezmoi/chezmoi.toml" <<EOF
[chezmoi]
  sourceDir = "$INSTALL_DIR/dotfiles"
EOF
say "configured chezmoi source → $INSTALL_DIR/dotfiles"

mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/kaizen" <<EOF
#!/bin/sh
export KAIZEN_INSTALL_MODE="$INSTALL_MODE"
exec "$PYTHON" "$INSTALL_DIR/kaizen.py" "\$@"
EOF
chmod +x "$BIN_DIR/kaizen"

case ":$PATH:" in
*":$BIN_DIR:"*) KAIZEN_COMMAND="kaizen" ;;
*)
	KAIZEN_COMMAND="$BIN_DIR/kaizen"
	say "add $BIN_DIR to your PATH to use kaizen without its full path"
	;;
esac

say ""
say "installed kaizen at $INSTALL_DIR"

if [ -n "${CONFIG_CREATED:-}" ] && (: </dev/tty) 2>/dev/null; then
	if ! open_config; then
		say "warning: could not open $editor"
	fi
	offer_sync
fi

if config_has_placeholders; then
	say "edit $CONFIG_FILE, then run: $KAIZEN_COMMAND sync"
	exit 0
fi

say "run when ready: $KAIZEN_COMMAND sync"
