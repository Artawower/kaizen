#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/nvim/lua"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/dot_config/nvim/lua/kaizen.lua.tmpl" "$source_dir/dot_config/nvim/lua/kaizen.lua.tmpl"
template="$source_dir/dot_config/nvim/lua/kaizen.lua.tmpl"

for layout in colemak qwerty colemak-regular; do
	rendered="$tmp_dir/kaizen-$layout.lua"
	chezmoi execute-template \
		--source "$source_dir" \
		--override-data "{\"layout\":\"$layout\"}" \
		--file "$template" >"$rendered"

	python3 - "$rendered" "$layout" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
layout = sys.argv[2]
text = path.read_text()

assert f'layout = "{layout}"' in text
if layout == "colemak":
    assert 'nav_down = "n"' in text
    assert 'nav_up = "e"' in text
    assert 'nav_right = "i"' in text
    assert 'nav_left = "h"' in text
    assert 'nav_insert = "l"' in text
else:
    assert 'nav_down = "j"' in text
    assert 'nav_up = "k"' in text
    assert 'nav_right = "l"' in text
    assert 'nav_left = "h"' in text
    assert 'nav_insert = "i"' in text
PY

	nvim --headless -u NONE -c "lua kaizen = dofile('$rendered')" -c "lua assert(type(kaizen) == 'table')" -c "lua if '$layout' == 'colemak' then assert(kaizen.has_colemak_rebinds()) else assert(not kaizen.has_colemak_rebinds()) end" -c "qa"
done

override_source="$tmp_dir/override_source"
mkdir -p "$override_source/dot_config/nvim/lua" "$override_source/.chezmoidata"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$override_source/.chezmoidata.toml"
cp "$repo_root/dotfiles/dot_config/nvim/lua/kaizen.lua.tmpl" "$override_source/dot_config/nvim/lua/kaizen.lua.tmpl"
cat >"$override_source/.chezmoidata/99-user.toml" <<'EOF'
layout = "colemak-regular"

[kaizen.shortcuts]
"file.find" = ["f", "custom"]
"nav.down" = ["s"]
EOF

rendered_override="$tmp_dir/kaizen-override.lua"
chezmoi execute-template \
	--source "$override_source" \
	--file "$override_source/dot_config/nvim/lua/kaizen.lua.tmpl" >"$rendered_override"

python3 - "$rendered_override" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
assert 'nav_down = "s"' in text
assert '"f",\n      "custom",' in text
PY

nvim --headless -u NONE -c "lua kaizen = dofile('$rendered_override')" -c "lua assert(kaizen.nav_down == 's')" -c "lua assert(kaizen.key('file.find') == 'fcustom')" -c "qa"

printf 'neovim config tests passed\n'
