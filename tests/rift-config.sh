#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/rift" "$source_dir/dot_config/mango"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/dot_config/rift/config.toml.tmpl" "$source_dir/dot_config/rift/config.toml.tmpl"
cp "$repo_root/dotfiles/dot_config/mango/config.conf.tmpl" "$source_dir/dot_config/mango/config.conf.tmpl"

for layout in colemak qwerty colemak-regular; do
    for variant in rift mango; do
        extension=toml
        if [[ "$variant" == mango ]]; then
            extension=conf
        fi
        chezmoi execute-template \
            --source "$source_dir" \
            --override-data "{\"layout\":\"$layout\"}" \
            --file "$source_dir/dot_config/$variant/config.$extension.tmpl" >"$tmp_dir/$variant-$layout"
    done
done

python3 - "$tmp_dir" <<'PY'
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
configs = {}
for layout in ("colemak", "qwerty", "colemak-regular"):
    config = tomllib.loads((root / f"rift-{layout}").read_text())
    configs[layout] = config
    keys = config["keys"]
    navigation = "HNEI" if layout == "colemak" else "HJKL"
    directions = ("left", "down", "up", "right")
    for key, direction in zip(navigation, directions):
        focus = keys[f"Alt + Shift + {key}"]
        if direction in {"left", "right"}:
            assert focus == {"exec": ["sh", "-c", f"~/.config/rift/scripts/focus-edge.sh {direction}"]}
        else:
            assert focus == {"move_focus": direction}
        assert keys[f"Meta + Alt + Shift + {key}"] == {"move_node": direction}
        resize = "shrink" if direction in {"left", "up"} else "grow"
        assert keys[f"Ctrl + Meta + Alt + Shift + {key}"] == f"resize_window_{resize}"

    workspaces = "STWODRULAP" if layout == "colemak" else "STWDIEXUAP"
    for workspace, key in enumerate(workspaces):
        assert keys[f"Alt + Shift + {key}"] == {"switch_to_workspace": workspace}
        assert keys[f"Meta + Alt + Shift + {key}"] == {
            "move_window_to_workspace": {"workspace": workspace, "follow": True}
        }

    for workspace, key in enumerate((*"1234567890", "Minus", "Equal")):
        assert keys[f"Alt + Shift + {key}"] == {"switch_to_workspace": workspace}
        assert keys[f"Meta + Alt + Shift + {key}"] == {
            "move_window_to_workspace": {"workspace": workspace, "follow": True}
        }

    assert keys["Alt + Shift + Q"] == "close_window"
    close = "X" if layout == "colemak" else "Q"
    assert keys[f"Meta + Alt + Shift + {close}"] == "close_window"
    assert keys["Alt + Shift + Slash"] == {"set_workspace_layout": {"mode": "scrolling"}}
    assert keys["Ctrl + Alt + Shift + R"] == "reload_config"
    assert config["virtual_workspaces"]["default_workspace_count"] == 12
    anki_dialog_rule = next(
        rule for rule in config["virtual_workspaces"]["app_rules"]
        if rule.get("app_name") == "anki" and "title_regex" in rule
    )
    assert anki_dialog_rule["manage"] is True
    assert anki_dialog_rule["floating"] is True
    bitwarden_rules = [
        rule for rule in config["virtual_workspaces"]["app_rules"]
        if rule.get("title_substring") == "Bitwarden"
    ]
    assert len(bitwarden_rules) == 1
    assert bitwarden_rules[0]["floating"] is True

    if layout != "colemak":
        mango = set((root / f"mango-{layout}").read_text().splitlines())
        for workspace, key in enumerate(workspaces[:9], start=1):
            assert f"bind=ALT+SHIFT,{key.lower()},view,{workspace}" in mango
            assert f"bind=SUPER+ALT+SHIFT,{key.lower()},tag,{workspace}" in mango
        for key, direction in zip(navigation.lower(), directions):
            assert f"bind=SUPER+ALT+SHIFT,{key},move_client,{direction}" in mango

assert configs["qwerty"] == configs["colemak-regular"]
for config in configs.values():
    assert {key: value for key, value in config.items() if key != "keys"} == {
        key: value for key, value in configs["colemak"].items() if key != "keys"
    }

print("Rift config tests passed")
PY
