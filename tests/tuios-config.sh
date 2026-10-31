#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$repo_root" python3 <<'PY'
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

repo = Path(os.environ["REPO_ROOT"])
source = repo / "dotfiles"
intent = tomllib.loads((repo / "config.example.toml").read_text())
legacy = tomllib.loads((source / "dot_config/herdr/config.toml").read_text())
assert intent["terminal"]["multiplexer"] == "tuios"

def run(*args, env=None):
    return subprocess.check_output(args, text=True, env=env)

def normalize(key):
    parts = key.replace("prefix+", "").split("+")
    char = parts.pop()
    mods = {"alt" if part == "opt" else part for part in parts}
    if char.isupper():
        mods.add("shift")
        char = char.lower()
    return (*sorted(mods), "-" if char == "minus" else char)

mapping = {
    "reload_config": "reload_config", "detach": "prefix_detach",
    "workspace_picker": "prefix_session_switcher", "new_workspace": "new_session",
    "rename_workspace": "rename_session", "close_workspace": "prefix_close_session",
    "new_tab": "new_workspace", "rename_tab": "rename_workspace",
    "close_tab": "close_workspace", "previous_tab": "prev_workspace",
    "next_tab": "next_workspace", "previous_workspace": "prev_session",
    "next_workspace": "next_session", "focus_pane_left": "terminal_focus_left",
    "focus_pane_down": "terminal_focus_down", "focus_pane_up": "terminal_focus_up",
    "focus_pane_right": "terminal_focus_right", "split_vertical": "prefix_split_vertical",
    "split_horizontal": "prefix_split_horizontal", "close_pane": "prefix_close_window",
    "zoom": "prefix_fullscreen", "resize_mode": "prefix_layout",
    "toggle_sidebar": "prefix_toggle_sidebar",
}

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    home = root / "home"
    shared = home / ".config/tuios/shared.toml"
    shared.parent.mkdir(parents=True)
    env = {**os.environ, "HOME": str(home)}
    env.pop("XDG_CONFIG_HOME", None)
    config = root / "chezmoi.toml"
    config.write_text("")
    chezmoi = ["chezmoi", "--config", str(config), "--source", str(source),
               "--destination", str(home), "--persistent-state", str(root / "state.db"),
               "--cache", str(root / "cache"), "--no-tty"]
    rendered = run(*chezmoi, "execute-template", "--file",
                   str(source / "dot_config/tuios/shared.toml.tmpl"))
    data = tomllib.loads(rendered)
    theme = intent["ui"]["theme"]
    defaults = tomllib.loads((source / ".chezmoidata.toml").read_text())
    assert defaults["ui"]["theme"] == theme and theme["auto_switch"]
    assert data["appearance"]["theme"] == theme["dark"].replace("-", "_")
    assert data["appearance"]["theme_light"] == theme["light"].replace("-", "_")
    registered = {line.strip() for line in run("tuios", "--list-themes").splitlines()}
    for preferences in (theme, {"dark": "catppuccin-macchiato", "light": "gruvbox-light",
                                "auto_switch": True}, {**theme, "auto_switch": False}):
        override = json.dumps({"ui": {"theme": preferences}})
        variant = tomllib.loads(run(*chezmoi, "execute-template", "--override-data", override,
                                   "--file", str(source / "dot_config/tuios/shared.toml.tmpl")))
        dark = preferences["dark"].replace("-", "_")
        light = preferences["light"].replace("-", "_") if preferences["auto_switch"] else ""
        assert variant["appearance"]["theme"] == dark and dark in registered
        assert variant["appearance"]["theme_light"] == light
        assert not light or light in registered
    shell = data["appearance"]["preferred_shell"]
    assert Path(shell).is_absolute() and Path(shell).is_file(), shell
    assert shell == shutil.which(intent["terminal"]["shell"])
    assert "preferred_shell" not in data["daemon"]
    assert data["startup"]["layout"] == "bsp"
    assert data["startup"]["start_in_terminal_mode"]
    assert data["workspaces"]["new_window_when_empty"]
    assert data["notifications"]["agent"]["notify"]
    shared.write_text(rendered)

    linux_wrapper = source / "dot_config/tuios/private_config.toml"
    mac_wrapper = source / "private_Library/private_Application Support/private_tuios/private_config.toml"
    assert linux_wrapper.read_text() == mac_wrapper.read_text()
    assert tomllib.loads(mac_wrapper.read_text())["include"] == ["~/.config/tuios/shared.toml"]
    native = home / ("Library/Application Support/tuios/config.toml"
                     if sys.platform == "darwin" else ".config/tuios/config.toml")
    native.parent.mkdir(parents=True, exist_ok=True)
    native.write_text(mac_wrapper.read_text())
    files = run("tuios", "config", "files", env=env)
    assert str(shared) in files and str(native) in files, files
    xdg_entry = home / ".config/tuios/config.toml"
    xdg_entry.write_text(linux_wrapper.read_text())
    xdg_env = {**env, "XDG_CONFIG_HOME": str(home / ".config")}
    files = run("tuios", "config", "files", env=xdg_env)
    assert str(shared) in files and str(xdg_entry) in files, files
    report = json.loads(run("tuios", "keybinds", "doctor", "--json", env=env))
    for field in ("key_problems", "command_problems", "copy_mode_problems",
                  "collisions", "ambiguous_bindings"):
        assert not report[field], (field, report[field])
    assert report["leader"] == "ctrl+b"
    rows = json.loads(run("tuios", "keybinds", "list", "--json", env=env))

    def effective(action, prefixed=False):
        keys = []
        for row in rows:
            if row["action"] != action:
                continue
            if prefixed and row["section"] == "prefix_mode":
                keys.extend(key.removeprefix("ctrl+b ") for key in row["keys"])
            elif not prefixed and row["section"] in ("global", "terminal_mode"):
                keys.extend(row["keys"])
        return {normalize(key) for key in keys}

    assert set(legacy["keys"]) == set(mapping) | {"prefix", "switch_tab", "open_worktree",
                                                   "command", "indexed"}
    for command in legacy["keys"]["command"]:
        if command["command"] == "herdr-tmux-layout.balance":
            assert normalize(command["key"]) in effective("prefix_equalize_splits", True)
        else:
            assert command["command"] == "herdr-tmux-layout.tiled"
            assert normalize(command["key"]) == normalize(data["keybindings"]["command"][0]["key"])

    for old, action in mapping.items():
        for key in legacy["keys"][old]:
            prefixed = key.startswith("prefix+")
            if not prefixed and "super+shift" not in key:
                continue
            target = action
            if not prefixed and old in ("close_pane", "zoom"):
                target = {"close_pane": "close_window", "zoom": "toggle_zoom"}[old]
            assert normalize(key) in effective(target, prefixed), (old, key, target)
    layer = "super+alt+shift" if sys.platform == "darwin" else "ctrl+alt+shift"
    for direction, latin, cyrillic in (("left", "h", "р"), ("down", "j", "н"),
                                       ("up", "k", "т"), ("right", "l", "г")):
        keys = effective(f"terminal_focus_{direction}")
        assert normalize(f"{layer}+{latin}") in keys
        assert normalize(f"{layer}+{cyrillic}") in keys
        assert normalize(f"opt+{latin}") not in keys
    assert normalize("super+b") not in effective("prefix_toggle_sidebar")
    for action, latin, cyrillic in (("prefix_session_switcher", "w", "ц"), ("new_workspace", "t", "а"),
                                    ("rename_workspace", "r", "ы"), ("close_workspace", "x", "ч"),
                                    ("close_window", "d", "п"), ("toggle_zoom", "f", "у"),
                                    ("terminal_next_window", "n", "о"), ("terminal_prev_window", "p", "к")):
        keys = effective(action)
        assert normalize(f"{layer}+{latin}") in keys
        assert normalize(f"{layer}+{cyrillic}") in keys
    assert normalize("b") in effective("prefix_toggle_sidebar", True)
    for index in range(1, 10):
        assert normalize(f"{layer}+{index}") in effective(f"switch_workspace_{index}")
        assert normalize(str(index)) in effective(f"switch_workspace_{index}", True)
        assert normalize(f"ctrl+{index}") in effective(f"switch_session_{index}")

    command = data["keybindings"]["command"][0]
    assert command["key"] == "prefix+opt+5" and command["type"] == "shell"
    subprocess.run(["sh", "-n", "-c", command["command"]], check=True)
    binary = root / "bin/tuios"
    binary.parent.mkdir()
    binary.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
    binary.chmod(0o755)
    session = "a session; not a command"
    stub_env = {**env, "PATH": str(binary.parent), "TUIOS_SESSION": session}
    args = run(shutil.which("sh"), "-c", command["command"], env=stub_env).splitlines()
    assert args == ["run-command", "ArrangePanes", "tiled", "-s", session], args

    taken = {normalize(row["key"]) for row in report["terminal_mode_swallowed"]}
    assert normalize("ctrl+p") not in taken
    for key in ("h", "j", "k", "l", "р", "н", "т", "г"):
        assert normalize(f"ctrl+alt+{key}") not in taken

    for section, actions in data["keybindings"].items():
        if not isinstance(actions, dict):
            continue
        for action, keys in actions.items():
            normalized = {normalize(key) for key in keys}
            for key in keys:
                parts = key.split("+")
                char = parts[-1]
                alias = intent["keyboard"]["aliases"]["ru"].get(char.lower())
                if alias and char.isalpha():
                    parts[-1] = alias.upper() if char.isupper() else alias
                    assert normalize("+".join(parts)) in normalized, (section, action, key)

print("TUIOS rendering, automatic themes, migration, aliases and effective binding checks passed")
PY
