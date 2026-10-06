#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/xonsh"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/.chezmoiignore.tmpl" "$source_dir/.chezmoiignore.tmpl"
cp "$repo_root/dotfiles/dot_config/xonsh/keybindings.xsh.tmpl" "$source_dir/dot_config/xonsh/keybindings.xsh.tmpl"
template="$source_dir/dot_config/xonsh/keybindings.xsh.tmpl"

for layout in colemak qwerty colemak-regular; do
    rendered="$tmp_dir/keybindings-$layout.xsh"
    chezmoi execute-template \
        --source "$source_dir" \
        --override-data "{\"layout\":\"$layout\"}" \
        --file "$template" >"$rendered"

    python3 -m py_compile "$rendered"
    grep -qF 'exec(_load_module("keybindings_shared.xsh"))' "$rendered"
    ! grep -qF 'data.toml' "$rendered"

    if [[ "$layout" == colemak ]]; then
        grep -qF 'exec(_load_module("keybindings_colemak.xsh"))' "$rendered"
        ! grep -qF 'exec(_load_module("keybindings_qwerty.xsh"))' "$rendered"
    else
        grep -qF 'exec(_load_module("keybindings_qwerty.xsh"))' "$rendered"
        ! grep -qF 'exec(_load_module("keybindings_colemak.xsh"))' "$rendered"
    fi
done

echo "xonsh config tests passed"
