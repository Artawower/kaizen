#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/xremap"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/.chezmoiignore.tmpl" "$source_dir/.chezmoiignore.tmpl"
cp "$repo_root/dotfiles/dot_config/xremap/config.yml.tmpl" "$source_dir/dot_config/xremap/config.yml.tmpl"
template="$source_dir/dot_config/xremap/config.yml.tmpl"

for layout in colemak qwerty colemak-regular; do
	rendered="$tmp_dir/xremap-$layout.yml"
	chezmoi execute-template \
		--source "$source_dir" \
		--override-data "{\"layout\":\"$layout\"}" \
		--file "$template" >"$rendered"

	python3 - "$rendered" <<'PY'
import sys
from pathlib import Path

content = Path(sys.argv[1]).read_text()
assert "Alt-Backspace: C-w" in content
assert "Alt-Delete: C-w" in content
assert "- name: Fn tabs" in content
assert "Super-z: C-z- name: Fn tabs" not in content
PY

	if [[ -x /usr/bin/xremap ]]; then
		/usr/bin/xremap --validate-config "$rendered"
	fi
done

echo "xremap config tests passed"
