#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$repo_root/dotfiles/dot_config/aerospace/aerospace.toml.tmpl"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for layout in colemak qwerty; do
    rendered="$tmp_dir/aerospace-$layout.toml"
    chezmoi execute-template \
        --source "$repo_root/dotfiles" \
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
assert config["key-mapping"]["preset"] == layout

main = config["mode"]["main"]["binding"]
service = config["mode"]["service"]["binding"]
nav = {
    "colemak": {"h": "left", "n": "down", "e": "up", "i": "right"},
    "qwerty": {"h": "left", "j": "down", "k": "up", "l": "right"},
}[layout]

for key, direction in nav.items():
    assert f"alt-shift-{key}" in main
    assert f"cmd-alt-shift-{key}" in main
    assert service[key] == [f"join-with {direction}", "mode main"]

resizes = {
    "left": "resize width -40",
    "down": "resize height +40",
    "up": "resize height -40",
    "right": "resize width +40",
}
for key, command in resizes.items():
    assert main[f"ctrl-alt-shift-{key}"] == command

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
