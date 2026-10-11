#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/private_karabiner"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/dot_config/private_karabiner/karabiner.json.tmpl" "$source_dir/dot_config/private_karabiner/karabiner.json.tmpl"
template="$source_dir/dot_config/private_karabiner/karabiner.json.tmpl"

for layout in colemak qwerty colemak-regular; do
    rendered="$tmp_dir/karabiner-$layout.json"
    chezmoi execute-template \
        --source "$source_dir" \
        --override-data "{\"layout\":\"$layout\"}" \
        --file "$template" >"$rendered"

    python3 - "$rendered" "$layout" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
layout = sys.argv[2]
rules = config["profiles"][0]["complex_modifications"]["rules"]
expected = {"j": "j", "k": "k", "l": "l"}
if layout == "colemak-regular":
    expected = {"j": "y", "k": "n", "l": "u"}

def rule_containing(fragment):
    return next(rule for rule in rules if fragment in rule.get("description", "") or fragment in rule.get("title", ""))

def input_keys(rule):
    return [item["from"]["key_code"] for item in rule["manipulators"]]

arrow_rule = rule_containing("ctrl+cmd navigation")
assert input_keys(arrow_rule) == [expected["k"], expected["j"], "h", expected["l"]] * 2
arrow_outputs = [item["to"][0]["key_code"] for item in arrow_rule["manipulators"]]
assert arrow_outputs == ["up_arrow", "down_arrow", "left_arrow", "right_arrow"] * 2
assert all("shift" in item["from"]["modifiers"]["mandatory"] for item in arrow_rule["manipulators"][4:])
assert all(item["to"][0]["modifiers"] == ["shift"] for item in arrow_rule["manipulators"][4:])

browser_rule = rule_containing("Browsers: tab navigation")
assert input_keys(browser_rule)[:2] == [expected["j"], expected["k"]]
browser_outputs = [item["to"][0]["modifiers"] for item in browser_rule["manipulators"][:2]]
assert browser_outputs == [["left_control"], ["left_control", "left_shift"]]

kagi_rule = rule_containing("Kagi Search")
assert input_keys(kagi_rule) == [expected["j"], expected["k"]]

telegram_rule = rule_containing("Shift + Tab")
assert input_keys(telegram_rule) == [expected["j"], expected["k"]]

fn_rule = rule_containing("Map fn+")
assert input_keys(fn_rule) == [expected["k"], expected["j"], "h", expected["l"]]
PY
done

echo "Karabiner config tests passed"
