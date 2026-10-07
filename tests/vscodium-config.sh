#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/.chezmoitemplates/vscodium"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/.chezmoiignore.tmpl" "$source_dir/.chezmoiignore.tmpl"
cp "$repo_root/dotfiles/.chezmoitemplates/vscodium/settings.json.tmpl" "$source_dir/.chezmoitemplates/vscodium/settings.json.tmpl"
cp "$repo_root/dotfiles/.chezmoitemplates/vscodium/keybindings.json.tmpl" "$source_dir/.chezmoitemplates/vscodium/keybindings.json.tmpl"

for layout in colemak qwerty colemak-regular; do
    settings="$tmp_dir/settings-$layout.json"
    keybindings="$tmp_dir/keybindings-$layout.json"
    chezmoi execute-template \
        --source "$source_dir" \
        --override-data "{\"layout\":\"$layout\"}" \
        --file "$source_dir/.chezmoitemplates/vscodium/settings.json.tmpl" >"$settings"
    chezmoi execute-template \
        --source "$source_dir" \
        --override-data "{\"layout\":\"$layout\"}" \
        --file "$source_dir/.chezmoitemplates/vscodium/keybindings.json.tmpl" >"$keybindings"

    python3 - "$settings" "$keybindings" "$layout" <<'PY'
import json
import re
import sys
from pathlib import Path


def load_jsonc(path):
    text = Path(path).read_text()
    return json.loads(re.sub(r",\s*([}\]])", r"\1", text))


settings = load_jsonc(sys.argv[1])
keybindings = load_jsonc(sys.argv[2])
layout = sys.argv[3]
normal = {tuple(binding["before"]): binding for binding in settings["vim.normalModeKeyBindingsNonRecursive"]}
visual = {tuple(binding["before"]): binding for binding in settings["vim.visualModeKeyBindingsNonRecursive"]}
insert = {tuple(binding["before"]): binding for binding in settings["vim.insertModeKeyBindingsNonRecursive"]}
keys = {(binding["key"], binding["command"]) for binding in keybindings}

assert settings["window.autoDetectColorScheme"] is True
assert settings["workbench.preferredDarkColorTheme"] == "Catppuccin Mocha"
assert settings["workbench.preferredLightColorTheme"] == "Catppuccin Latte"
assert settings["workbench.colorTheme"] == "Catppuccin Mocha"
assert ("meta+[KeyS]", "workbench.action.files.save") in keys
assert ("meta+[KeyW]", "workbench.action.closeActiveEditor") in keys
assert ("meta+[KeyC]", "editor.action.clipboardCopyAction") in keys
assert ("meta+[KeyV]", "editor.action.clipboardPasteAction") in keys
assert ("ctrl+.", "workbench.action.focusNextGroup") in keys
assert all(any(code in key for code in ("[Key", "[Comma]", "[Slash]")) for key, _ in keys if key.startswith("meta+"))

if layout == "colemak":
    assert normal[("n",)]["after"] == ["g", "j"]
    assert normal[("e",)]["after"] == ["g", "k"]
    assert normal[("i",)]["after"] == ["l"]
    assert visual[("n",)]["after"] == ["g", "j"]
    assert ("<C-n>",) in insert
    assert ("<C-w>", "n") in normal
    assert ("ctrl+n", "selectNextSuggestion") in keys
    assert "у;f" in settings["vim.langmap"]
else:
    assert ("n",) not in normal
    assert ("e",) not in normal
    assert ("i",) not in normal
    assert ("n",) not in visual
    assert ("e",) not in visual
    assert ("i",) not in visual
    assert ("<C-j>",) in insert
    assert ("<C-k>",) in insert
    assert ("<C-w>", "j") in normal
    assert ("<C-w>", "k") in normal
    assert ("<C-w>", "l") in normal
    assert ("ctrl+j", "selectNextSuggestion") in keys
    assert ("ctrl+k", "selectPrevSuggestion") in keys

if layout == "qwerty":
    assert "у;e" in settings["vim.langmap"]
else:
    assert "у;f" in settings["vim.langmap"]
PY
done

echo "VSCodium config tests passed"
