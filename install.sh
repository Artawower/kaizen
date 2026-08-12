#!/bin/sh
set -eu

REPO="https://github.com/artawower/kaizen"
INSTALL_DIR="${KAIZEN_DIR:-$HOME/.local/share/kaizen}"
CONFIG_DIR="$HOME/.config/kaizen"
BIN_DIR="$HOME/.local/bin"

say() { printf '%s\n' "$*" >&2; }
die() {
	say "error: $*"
	exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "missing: $1"; }

need curl
need git
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

if [ -d "$INSTALL_DIR/.git" ]; then
	say "updating existing kaizen at $INSTALL_DIR"
	git -C "$INSTALL_DIR" pull --ff-only
else
	say "cloning kaizen to $INSTALL_DIR"
	git clone --depth=1 "$REPO" "$INSTALL_DIR"
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
*":$BIN_DIR:"*) ;;
*) say "add $BIN_DIR to your PATH to use the kaizen command" ;;
esac

say ""
say "installed kaizen at $INSTALL_DIR"
say "edit $CONFIG_DIR/config.toml, then run: kaizen sync"
