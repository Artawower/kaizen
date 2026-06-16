#!/usr/bin/env bash
set -euo pipefail

repo="Artawower/kaizen"
publish="true"
tag=""
release_dir="release/macos-local"
declare -a requested_targets=()

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
	cat <<'EOF'
Build macOS release archives locally and upload them to a GitHub release.

Usage:
  scripts/release-macos-local.sh [options]

Options:
  --repo OWNER/REPO   GitHub repository, default: Artawower/kaizen
  --tag TAG           Release tag, default: v<kaizen-cli version>
  --target TARGET     Build a specific Rust target, can be repeated
  --build-only        Build archives without uploading to GitHub
  -h, --help          Show this message
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--repo)
		[ "$#" -ge 2 ] || die "missing value for --repo"
		repo="$2"
		shift
		;;
	--tag)
		[ "$#" -ge 2 ] || die "missing value for --tag"
		tag="$2"
		shift
		;;
	--target)
		[ "$#" -ge 2 ] || die "missing value for --target"
		requested_targets+=("$2")
		shift
		;;
	--build-only)
		publish="false"
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

need cargo
need rustup
need tar
need sed
need shasum
need xcrun

os=$(uname -s)
[ "$os" = "Darwin" ] || die "this script supports macOS only"

version=$(sed -n 's/^version = "\([^"]*\)"/\1/p' crates/kaizen-cli/Cargo.toml | head -n 1)
[ -n "$version" ] || die "failed to detect version from crates/kaizen-cli/Cargo.toml"

if [ -z "$tag" ]; then
	tag="v$version"
fi

case "$tag" in
v*) ;;
*) tag="v$tag" ;;
esac

if [ "${#requested_targets[@]}" -eq 0 ]; then
	case "$(uname -m)" in
	arm64 | aarch64)
		requested_targets=("aarch64-apple-darwin" "x86_64-apple-darwin")
		;;
	x86_64)
		requested_targets=("x86_64-apple-darwin")
		;;
	*)
		die "unsupported macOS architecture: $(uname -m)"
		;;
	esac
fi

rm -rf "$release_dir"
mkdir -p "$release_dir"

clang=$(xcrun --find clang)
sdk_path=$(xcrun --show-sdk-path)
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="$clang"
export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$clang"
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-L $sdk_path/usr/lib"

for target in "${requested_targets[@]}"; do
	rustup target add "$target"
	cargo build --release --bin kaizen --target "$target"
	cp "target/$target/release/kaizen" "$release_dir/kaizen"
	tar -C "$release_dir" -czf "$release_dir/kaizen-$target.tar.gz" kaizen
	rm "$release_dir/kaizen"
	printf 'built %s\n' "$release_dir/kaizen-$target.tar.gz"
done

if [ "$publish" != "true" ]; then
	printf 'artifacts are in %s\n' "$release_dir"
	exit 0
fi

need gh

gh release view "$tag" --repo "$repo" >/dev/null 2>&1 || gh release create "$tag" --repo "$repo" --title "Kaizen ${tag#v}" --generate-notes

checksum_dir=$(mktemp -d "${TMPDIR:-/tmp}/kaizen-release.XXXXXX")
trap 'rm -rf "$checksum_dir"' EXIT HUP INT TERM
mkdir -p "$checksum_dir/current"

gh release download "$tag" --repo "$repo" --pattern 'kaizen-*-apple-darwin.tar.gz' --dir "$checksum_dir/current" >/dev/null 2>&1 || true

mkdir -p "$checksum_dir/final"
shopt -s nullglob
for file in "$checksum_dir"/current/kaizen-*-apple-darwin.tar.gz; do
	cp "$file" "$checksum_dir/final/$(basename "$file")"
done
for file in "$release_dir"/kaizen-*-apple-darwin.tar.gz; do
	cp "$file" "$checksum_dir/final/$(basename "$file")"
done

mapfile -t checksum_files < <(cd "$checksum_dir/final" && printf '%s\n' kaizen-*-apple-darwin.tar.gz | sort)
[ "${#checksum_files[@]}" -gt 0 ] || die "no macOS archives found to publish"

(
	cd "$checksum_dir/final"
	shasum -a 256 "${checksum_files[@]}" >kaizen-sha256.txt
)
cp "$checksum_dir/final/kaizen-sha256.txt" "$release_dir/kaizen-sha256.txt"

upload_files=("$release_dir"/kaizen-*.tar.gz "$release_dir/kaizen-sha256.txt")
gh release upload "$tag" --repo "$repo" --clobber "${upload_files[@]}"

printf 'uploaded %s to %s\n' "$tag" "$repo"
