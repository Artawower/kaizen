#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_dir="$tmp_dir/source"
mkdir -p "$source_dir/dot_config/mango"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$source_dir/.chezmoidata.toml"
cp "$repo_root/dotfiles/.chezmoiignore.tmpl" "$source_dir/.chezmoiignore.tmpl"
cp "$repo_root/dotfiles/dot_config/mango/config.conf.tmpl" "$source_dir/dot_config/mango/config.conf.tmpl"
template="$source_dir/dot_config/mango/config.conf.tmpl"

for layout in colemak qwerty; do
	rendered="$tmp_dir/mango-$layout.conf"
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
lines = set(text.splitlines())

assert "circle_layout=scroller,tile,dwindle" in lines
assert "env=WLR_RENDER_DRM_DEVICE,/dev/dri/renderD128" in lines
assert any(line.startswith("env=PATH,") and "/.local/bin:" in line for line in lines)
assert "exec-once=sh ~/.config/mango/autostart.sh" in lines
assert "xkb_rules_options=grp:caps_toggle,lv3:ralt_alt" in lines
assert "bind=ALT+SHIFT,v,switch_layout" in lines
assert "bind=ALT+SHIFT,slash,setlayout,scroller" in lines
assert "bind=ALT+SHIFT,comma,setlayout,tile" in lines
assert "bind=ALT+SHIFT,period,setlayout,dwindle" in lines
assert "bind=SUPER,space,spawn,vicinae vicinae://launch/clipboard/history?toggle=true" in lines
assert "bind=SUPER+SHIFT,space,spawn,vicinae vicinae://launch/core/search-emojis?toggle=true" in lines
assert "bind=CTRL,backslash,spawn_shell,hyprvoice toggle" in lines
assert "bind=CTRL+SHIFT,backslash,spawn,handy --toggle-transcription" in lines
assert "bind=SUPER+SHIFT,x,spawn_shell,grim -g \"$(slurp)\" - | satty --filename -" in lines
assert "bind=CTRL+SUPER,1,spawn_shell,grim - | satty --filename -" in lines
assert "bind=CTRL+SUPER,2,spawn_shell,grim -g \"$(slurp)\" - | satty --filename -" in lines
assert "source-optional=~/.config/mango/noctalia.conf" in lines
assert "monitorrule=name:^eDP-1$,width:3024,height:1964,refresh:60.004,x:0,y:1080,scale:2,rr:0" in lines
assert "monitorrule=name:^HDMI-A-1$,width:3840,height:2160,refresh:60,x:0,y:0,scale:2,rr:0" in lines
assert "mouse_accel_profile=2" in lines
assert "trackpad_natural_scrolling=0" in lines
assert "trackpad_scroll_factor=1.0" in lines
assert "tap_to_click=1" in lines
assert "tap_and_drag=1" in lines
assert "drag_lock=1" in lines
assert "trackpad_disable_while_typing=0" in lines
assert "swipe_min_threshold=1" in lines
assert "gesture_live=1" in lines
for direction in ("left", "right", "up", "down"):
    assert f"gesturebind=NONE,{direction},3,focusdir,{direction}" in lines
assert "gesturebind=NONE,right,4,viewtoleft,0" in lines
assert "gesturebind=NONE,left,4,viewtoright,0" in lines
assert "gesturebind=NONE,up,4,toggleoverview" in lines
assert "gesturebind=NONE,down,4,toggleoverview" in lines
assert "warpcursor=0" in lines
assert "edge_scroller_pointer_focus=0" in lines
assert "scroller_default_proportion_single=0.5" in lines
assert "scroller_focus_center=0" in lines
assert "borderpx=2" in lines
assert all(f"gapp{axis}=16" in lines for axis in ("ih", "iv", "oh", "ov"))
assert text.count("tagrule=id:") == 9
assert "windowrule=tags:1,appid:^(org\\.telegram\\.desktop|telegram-desktop|com\\.mattermost\\.Desktop|mattermost|discord|vesktop)$" in lines
assert "bind=SUPER+SHIFT,e,spawn,emacsclient -c -a emacs" not in lines
assert ("xkb_rules_variant=colemak," in lines) == (layout == "colemak")

navigation = {
    "colemak": {"h": "left", "n": "down", "e": "up", "i": "right"},
    "qwerty": {"h": "left", "j": "down", "k": "up", "l": "right"},
}[layout]
for key, direction in navigation.items():
    if direction in {"left", "right"}:
        assert f"bind=ALT+SHIFT,{key},focus_window_or_workspace,{direction}" in lines
    else:
        stack = "next" if direction == "down" else "prev"
        assert f"bind=ALT+SHIFT,{key},focusstack,{stack}" in lines
    assert f"bind=SUPER+ALT+SHIFT,{key},move_client,{direction}" in lines
    assert f"bind=CTRL+SUPER+ALT+SHIFT,{key},smartresizewin,{direction}" in lines

mnemonics = {
    "colemak": {"s": 1, "t": 2, "w": 3, "d": 4, "o": 5, "r": 6, "u": 7, "l": 8, "a": 9},
    "qwerty": {"s": 1, "t": 2, "w": 3, "d": 4, "i": 5, "e": 6, "x": 7, "u": 8, "a": 9},
}[layout]
for key, tag in mnemonics.items():
    assert f"bind=ALT+SHIFT,{key},view,{tag}" in lines
    assert f"bind=SUPER+ALT+SHIFT,{key},tag,{tag}" in lines

for tag in range(1, 10):
    assert f"bind=ALT+SHIFT,{tag},view,{tag}" in lines
    assert f"bind=SUPER+ALT+SHIFT,{tag},tag,{tag}" in lines
PY
done

for variant in mangowm niri; do
	rendered="$tmp_dir/ignore-$variant"
	chezmoi execute-template \
		--source "$source_dir" \
		--override-data "{\"features\":{\"tiling\":true},\"tiling\":{\"variant\":\"$variant\"}}" \
		--file "$source_dir/.chezmoiignore.tmpl" >"$rendered"
	if [[ "$variant" == mangowm ]]; then
		! grep -qxF '.config/mango/' "$rendered"
		grep -qxF '.config/niri/' "$rendered"
	else
		grep -qxF '.config/mango/' "$rendered"
		! grep -qxF '.config/niri/' "$rendered"
	fi
done

autostart="$repo_root/dotfiles/dot_config/mango/executable_autostart.sh"
bash -n "$autostart"
grep -qF 'export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"' "$autostart"
grep -qF 'xremap_bin=/usr/bin/xremap' "$autostart"
grep -qF 'xremap_bin="$HOME/.local/bin/xremap-wlroots"' "$autostart"
grep -qF '"$xremap_bin" --device '\''Apple SPI Keyboard'\'' --watch=config,device' "$autostart"
grep -qF 'dbus-update-activation-environment --systemd' "$autostart"
grep -qxF $'\tydotoold &' "$autostart"
grep -qxF $'\thandy --start-hidden &' "$autostart"
grep -qxF $'\t\temacs --daemon &' "$autostart"
grep -qF 'timeout 300 "noctalia msg session lock"' "$autostart"
grep -qF 'timeout 900 "systemctl suspend"' "$autostart"
grep -qF 'wl-paste --type image --watch cliphist store &' "$autostart"
! grep -Eq -- '--tablet|--gesture|--socket-path' "$autostart"

echo "MangoWM config tests passed"
