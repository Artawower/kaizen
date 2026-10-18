#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assert_absent() {
    if grep -qF "$1" "$2"; then
        printf 'Unexpected %s in %s\n' "$1" "$2" >&2
        return 1
    fi
}
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/noctalia"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/dot_config/noctalia/config.toml.tmpl" "$source_dir/dot_config/noctalia/config.toml.tmpl"
rendered="$tmp_dir/noctalia.toml"
chezmoi execute-template \
    --source "$source_dir" \
    --override-data '{"ui":{"wallpaper":{"directory":"~/Pictures/wallpappers","directory_light":"~/Pictures/wallpappers/light","directory_dark":"~/Pictures/wallpappers/dark"}}}' \
    --file "$source_dir/dot_config/noctalia/config.toml.tmpl" >"$rendered"
if command -v noctalia >/dev/null; then
    noctalia config validate "$rendered"
else
    printf 'Noctalia binary validation skipped: executable unavailable\n'
fi
python3 - "$rendered" <<'PY'
import sys
import tomllib
from pathlib import Path

with Path(sys.argv[1]).open("rb") as file:
    config = tomllib.load(file)

assert config["wallpaper"] == {
    "directory": "~/Pictures/wallpappers",
    "directory_light": "~/Pictures/wallpappers/light",
    "directory_dark": "~/Pictures/wallpappers/dark",
}
assert config["theme"]["mode"] == "auto"
assert config["idle"]["behavior"]["lock"] == {
    "enabled": True,
    "timeout": 300,
    "action": "lock",
}
assert config["idle"]["behavior"]["suspend"] == {
    "timeout": 900,
    "locked_timeout": 600,
    "action": "lock_and_suspend",
}
assert config["lockscreen"]["lock_before_suspend"] is True
PY

hook="$repo_root/dotfiles/dot_config/noctalia/scripts/executable_sync-system-appearance"
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/noctalia" <<'SH'
#!/usr/bin/env bash
printf 'noctalia %s\n' "$*" >>"$NOCTALIA_TEST_LOG"
if [[ "$*" == 'msg theme-mode-get' ]]; then
    printf 'dark\n'
fi
SH
cat >"$tmp_dir/bin/gsettings" <<'SH'
#!/usr/bin/env bash
printf 'gsettings %s\n' "$*" >>"$NOCTALIA_TEST_LOG"
SH
cat >"$tmp_dir/bin/vicinae" <<'SH'
#!/usr/bin/env bash
printf 'vicinae %s\n' "$*" >>"$NOCTALIA_TEST_LOG"
SH
chmod +x "$tmp_dir/bin/noctalia" "$tmp_dir/bin/gsettings" "$tmp_dir/bin/vicinae"
NOCTALIA_TEST_LOG="$tmp_dir/calls.log" PATH="$tmp_dir/bin:$PATH" python3 "$hook"
rg -q '^noctalia msg wallpaper-random$' "$tmp_dir/calls.log"
python3 - "$hook" <<'PY'
import sys
from pathlib import Path

compile(Path(sys.argv[1]).read_text(), sys.argv[1], "exec")
PY
assert_absent swayidle "$repo_root/features/tiling/packages.toml"
assert_absent swayidle "$repo_root/dotfiles/dot_config/scripts/executable_setup-fedora-deps"
assert_absent swayidle "$repo_root/dotfiles/dot_config/mango/executable_autostart.sh"
assert_absent swayidle "$repo_root/dotfiles/dot_config/niri/config.kdl.tmpl"
assert_absent swayidle "$repo_root/dotfiles/dot_config/hypr/hyprland.conf"
[[ ! -e "$repo_root/dotfiles/dot_config/private_net.imput.helium/video-idle-inhibit" ]]
printf 'Noctalia config tests passed\n'
