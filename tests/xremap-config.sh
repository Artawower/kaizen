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

	python3 - "$rendered" "$repo_root/dotfiles/dot_config/ghostty/config.tmpl" "$repo_root/dotfiles/dot_local/share/vicinae/scripts/executable_reload-xremap.py" "$layout" <<'PY'
import sys
from pathlib import Path

content = Path(sys.argv[1]).read_text()
arrows = content.split("- name: Ctrl+Super arrows", 1)[1].split("- name: Common Super shortcuts", 1)[0]
if sys.argv[4] == "colemak-regular":
    assert "Ctrl-Super-y: Down" in arrows
    assert "Ctrl-Super-n: Up" in arrows
    assert "Ctrl-Super-u: Right" in arrows
    assert "Ctrl-Super-j: Down" not in arrows
else:
    assert "Ctrl-Super-j: Down" in arrows
assert "Alt-Backspace: C-w" in content
assert "Alt-Delete: C-w" in content
terminal_delete = content.split("- name: Terminal word deletion", 1)[1].split("- name: Alt-Backspace delete word", 1)[0]
assert "ghostty" not in terminal_delete
assert "com.mitchellh.ghostty" not in terminal_delete
alt_backspace = content.split("- name: Alt-Backspace delete word", 1)[1].split("- name: Delete", 1)[0]
assert "ghostty" in alt_backspace
assert "com.mitchellh.ghostty" in alt_backspace
assert "Alt-Backspace: C-Backspace" in alt_backspace
delete = content.split("- name: Delete", 1)[1].split("- name: GUI shortcuts", 1)[0]
assert "Alt-Backspace" not in delete
ghostty_config = Path(sys.argv[2]).read_text()
assert r"keybind = alt+delete=text:\x17" in ghostty_config
assert r"keybind = ctrl+backspace=text:\x17" in ghostty_config
reload_script = Path(sys.argv[3]).read_text()
assert '"--device", "Apple SPI Keyboard", "--watch=config,device", config_path' in reload_script
assert '["xremap", config_path]' not in reload_script
assert "- name: Fn tabs" in content
assert "Super-z: C-z- name: Fn tabs" not in content
PY

	if [[ -x /usr/bin/xremap ]]; then
		/usr/bin/xremap --validate-config "$rendered"
	fi
done

echo "xremap config tests passed"
