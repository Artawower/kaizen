#!/bin/sh
set -eu

repo="artawower/kaizen"
crate="kaizen"
force="false"
tag=""
dest=""

say() {
	printf '%s\n' "$*" >&2
}

die() {
	say "error: $*"
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
	cat <<EOF
Install the latest Kaizen release for macOS.

Usage:
  install.sh [--tag VERSION] [--to DIR] [--force]

Options:
  --tag VERSION  Install a specific release tag
  --to DIR       Install to a specific directory
  --force        Overwrite an existing binary
  -h, --help     Show this message
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--tag)
		[ "$#" -ge 2 ] || die "missing value for --tag"
		tag="$2"
		shift
		;;
	--to)
		[ "$#" -ge 2 ] || die "missing value for --to"
		dest="$2"
		shift
		;;
	--force | -f)
		force="true"
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
	shift
done

need curl
need install
need mktemp
need tar
need uname

os=$(uname -s)
[ "$os" = "Darwin" ] || die "the installer currently supports macOS only"

arch=$(uname -m)
case "$arch" in
arm64 | aarch64)
	target="aarch64-apple-darwin"
	;;
x86_64)
	target="x86_64-apple-darwin"
	;;
*)
	die "unsupported architecture: $arch"
	;;
esac

if [ -n "$tag" ]; then
	case "$tag" in
	v*) ;;
	*) tag="v$tag" ;;
	esac
fi

if [ -z "$dest" ]; then
	if command -v brew >/dev/null 2>&1; then
		prefix=$(brew --prefix 2>/dev/null || true)
		if [ -n "$prefix" ]; then
			dest="$prefix/bin"
		fi
	fi
fi

if [ -z "$dest" ]; then
	dest="/usr/local/bin"
fi

if [ -n "$tag" ]; then
	base_url="https://github.com/$repo/releases/download/$tag"
else
	base_url="https://github.com/$repo/releases/latest/download"
fi

asset="$crate-$target.tar.gz"
url="$base_url/$asset"

sudo_cmd=""

if [ ! -d "$dest" ]; then
	if mkdir -p "$dest" 2>/dev/null; then
		:
	elif command -v sudo >/dev/null 2>&1; then
		sudo_cmd="sudo"
		"$sudo_cmd" mkdir -p "$dest"
	else
		dest="$HOME/.local/bin"
		mkdir -p "$dest"
	fi
fi

if [ ! -w "$dest" ] && [ -z "$sudo_cmd" ]; then
	if command -v sudo >/dev/null 2>&1; then
		sudo_cmd="sudo"
	else
		dest="$HOME/.local/bin"
		mkdir -p "$dest"
	fi
fi

binary_path="$dest/$crate"
if [ -e "$binary_path" ] && [ "$force" != "true" ]; then
	die "$binary_path already exists; rerun with --force to overwrite"
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/kaizen.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

say "downloading $url"
curl -fsSL "$url" -o "$tmpdir/$asset"
tar -xzf "$tmpdir/$asset" -C "$tmpdir"

[ -x "$tmpdir/$crate" ] || die "archive did not contain $crate"

if [ -n "$sudo_cmd" ]; then
	"$sudo_cmd" install -m 755 "$tmpdir/$crate" "$binary_path"
else
	install -m 755 "$tmpdir/$crate" "$binary_path"
fi

say "installed $crate to $binary_path"
case ":$PATH:" in
*":$dest:"*) ;;
*) say "add $dest to your PATH if the command is not available yet" ;;
esac
