#!/bin/sh
set -eu

REPO="${KAIZEN_REPO:-https://github.com/artawower/kaizen.git}"
REF="${KAIZEN_REF:-master}"
INSTALL_DIR="${KAIZEN_DIR:-$HOME/.local/share/kaizen}"
SOURCE_DIR="${KAIZEN_SOURCE_DIR:-}"
CONFIG_DIR="$HOME/.config/kaizen"
BIN_DIR="$HOME/.local/bin"

say() { printf '%s\n' "$*" >&2; }
die() {
	say "error: $*"
	exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "missing: $1"; }

need python3

python_ok() {
	python3 -c "import sys,tomllib; assert sys.version_info >= (3,11)" 2>/dev/null
}

python_ok || die "python 3.11+ required (current: $(python3 --version))"

OS=$(uname -s)
case "$OS" in
Darwin) need brew ;;
Linux)
	command -v dnf >/dev/null 2>&1 || command -v apt >/dev/null 2>&1 ||
		die "supported package managers: dnf, apt"
	;;
*) die "unsupported OS: $OS" ;;
esac

if [ -n "$SOURCE_DIR" ]; then
	SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
	[ -f "$SOURCE_DIR/kaizen.py" ] || die "kaizen.py not found in $SOURCE_DIR"
	[ -f "$SOURCE_DIR/config.example.toml" ] || die "config.example.toml not found in $SOURCE_DIR"
	INSTALL_DIR="$SOURCE_DIR"
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
if [ ! -f "$CONFIG_DIR/config.toml" ]; then
	cp "$INSTALL_DIR/config.example.toml" "$CONFIG_DIR/config.toml"
	say "created $CONFIG_DIR/config.toml — edit it to enable features"
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
exec python3 "$INSTALL_DIR/kaizen.py" "\$@"
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
say "edit $CONFIG_DIR/config.toml, then run: $KAIZEN_COMMAND sync"
