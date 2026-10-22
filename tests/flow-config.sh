#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$repo_root" <<'PY'
import json
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
flow = root / "dotfiles/dot_config/flow"
intent = tomllib.loads((root / "config.example.toml").read_text())
aliases = intent["keyboard"]["aliases"]["ru"]
aliases.update({key.upper(): value.upper() for key, value in list(aliases.items()) if key.isalpha()})
aliases.update({key: aliases[value].upper() for key, value in zip('~:{}<>"', '`;[],.\'')})

def russian(sequence):
    return " ".join("+".join(aliases.get(part, part) for part in key.split("+")) for key in sequence.split())

def merge(bindings, fallback):
    result = list(bindings)
    for binding in fallback:
        keys = binding[0].split()
        if not any(keys[:len(other[0].split())] == other[0].split() or other[0].split()[:len(keys)] == keys for other in result):
            result.append(binding)
    return result

profiles = {name: json.loads((flow / f"keys/{name}.json").read_text()) for name in ("helix", "kaizen")}
assert 'input_mode "kaizen"' in (flow / "config").read_text()
assert profiles["kaizen"]["settings"]["inherit"] == "helix"

for name, profile in profiles.items():
    assert (flow / f"keys/{name}.json").stat().st_size < 64 * 1024
    for mode, section in profile.items():
        bindings = section.get("press", [])
        keys = [binding[0] for binding in bindings]
        assert len(keys) == len(set(keys)), (name, mode, "duplicate binding")
        for key in keys:
            assert not any(other.startswith(key + " ") for other in keys), (name, mode, key, "prefix collision")

for mode in ("normal", "select", "insert", "mini/replace", "home"):
    base = profiles["helix"][mode]
    custom = profiles["kaizen"].get(mode, {})
    bindings = merge(custom.get("press", []), base["press"])
    effective = {binding[0]: binding[1:] for binding in bindings}
    for binding in bindings:
        alias = russian(binding[0])
        if alias != binding[0] and not any("\u0400" <= char <= "\u04ff" for char in binding[0]):
            assert effective.get(alias) == binding[1:], (mode, binding[0], alias, "Russian alias mismatch")
    if mode in ("normal", "select"):
        expected = {
            "h": ["move_left" if mode == "normal" else "select_left_helix"],
            "j": ["move_down" if mode == "normal" else "select_down"],
            "k": ["move_up" if mode == "normal" else "select_up"],
            "l": ["move_right" if mode == "normal" else "select_right_helix"],
            "i": ["enter_mode", "insert"],
            "0": ["move_begin" if mode == "normal" else "select_begin"],
            "$": ["move_end" if mode == "normal" else "select_end"],
            "space b b": ["switch_buffers"],
            "space f f": ["find_file"],
            "space l d": ["show_diagnostics"],
            "space l f": ["format"],
            "space l h": ["hover"],
            "space l r": ["rename_symbol"],
            "space l s": ["show_symbols"],
            "] d": ["goto_next_diagnostic"],
            "] g": ["goto_next_change"],
            "] t": ["goto_next_class"],
            "space [": ["previous_tab"],
            "space ]": ["next_tab"],
        }
        for key, command in expected.items():
            assert effective.get(key) == command, (mode, key, effective.get(key), command)
        for key in ("space b", "space f", "space l", "space r", "space p"):
            assert key not in effective, (mode, key, "shadows a shared prefix")
        assert custom["on_match_failure"] == "ignore"
        assert custom["selection"] == "inclusive"
        if mode == "select":
            assert custom["init_command"] == ["enable_selection"]
    if mode in ("insert", "mini/replace"):
        assert all("+" in binding[0] or not any("\u0400" <= char <= "\u04ff" for char in binding[0]) for binding in bindings), (mode, "plain Russian text intercepted")

assert russian("h j k l i") == "р н т г д"
assert russian("space l r") == "space г ы"
assert russian("ctrl+w L") == "ctrl+ц Г"
assert russian("alt+J") == "alt+Н"
assert russian(": { } < > ~ \"") == "З Х Ъ Б Ю Ё Э"
print("Flow keymap tests passed")
PY
