#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/aerospace"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/dot_config/aerospace/aerospace.toml.tmpl" "$source_dir/dot_config/aerospace/aerospace.toml.tmpl"
template="$source_dir/dot_config/aerospace/aerospace.toml.tmpl"

for layout in colemak qwerty colemak-regular; do
    rendered="$tmp_dir/aerospace-$layout.toml"
    chezmoi execute-template \
        --source "$source_dir" \
        --override-data "{\"layout\":\"$layout\"}" \
        --file "$template" >"$rendered"

    python3 - "$rendered" "$layout" <<'PY'
import sys
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
layout = sys.argv[2]
text = path.read_text()
with path.open("rb") as file:
    config = tomllib.load(file)

assert config["config-version"] == 2
assert config["after-startup-command"] == []
assert "borders" not in text
expected_preset = "colemak" if layout == "colemak" else "qwerty"
assert config["key-mapping"]["preset"] == expected_preset

main = config["mode"]["main"]["binding"]
service = config["mode"]["service"]["binding"]
nav = {
    "colemak": {"h": "left", "n": "down", "e": "up", "i": "right"},
    "qwerty": {"h": "left", "j": "down", "k": "up", "l": "right"},
    "colemak-regular": {"h": "left", "j": "down", "k": "up", "l": "right"},
}[layout]

resizes = {
    "left": "resize width -40",
    "down": "resize height +40",
    "up": "resize height -40",
    "right": "resize width +40",
}
for key, direction in nav.items():
    assert f"alt-shift-{key}" in main
    assert f"cmd-alt-shift-{key}" in main
    assert main[f"ctrl-cmd-alt-shift-{key}"] == resizes[direction]
    assert service[key] == [f"join-with {direction}", "mode main"]

for modifiers in ("alt-shift", "cmd-alt-shift", "ctrl-alt-shift"):
    for arrow in ("left", "down", "up", "right"):
        assert f"{modifiers}-{arrow}" not in main

workspaces = {
    "1": "SOC",
    "2": "TRM",
    "3": "WEB",
    "4": "DEB",
    "5": "DEV",
    "6": "ENT",
    "7": "THR",
    "8": "STU",
    "9": "AI",
    "0": "PRD",
}
for key, workspace in workspaces.items():
    assert main[f"alt-shift-{key}"] == f"workspace {workspace}"
    assert main[f"cmd-alt-shift-{key}"] == [
        f"move-node-to-workspace {workspace}",
        f"workspace {workspace}",
    ]

assert main["alt-shift-q"] == "close"
assert main["alt-shift-f"] == "fullscreen"
assert "Ghostty.app" in main["alt-shift-enter"]
assert "wallboy next" in main["ctrl-alt-shift-i"]
assert "wallboy save" in main["ctrl-alt-shift-d"]
assert "wallboy open" in main["ctrl-alt-shift-o"]
PY
done

echo "aerospace config tests passed"
