#!/bin/sh
set -eu

scale="${1:-0.8}"

window="$(rift-cli query windows | jq -c 'map(select(.is_focused == true))[0] // empty')"

rift-cli execute window toggle-float >/dev/null

[ -n "$window" ] || exit 0
[ "$(printf '%s' "$window" | jq -r '.is_floating')" = "false" ] || exit 0

pid="$(printf '%s' "$window" | jq -r '.id.pid')"
geometry="$(
  rift-cli query displays |
    jq -r --argjson w "$window" --argjson s "$scale" '
      $w.frame as $f
      | ($f.origin.x + $f.size.width / 2) as $cx
      | ($f.origin.y + $f.size.height / 2) as $cy
      | (map(select(
          .frame.origin.x <= $cx and $cx < .frame.origin.x + .frame.size.width
          and .frame.origin.y <= $cy and $cy < .frame.origin.y + .frame.size.height
        ))[0] // .[0]).frame as $d
      | ($f.size.width * $s | floor) as $width
      | ($f.size.height * $s | floor) as $height
      | [
          ($d.origin.x + ($d.size.width - $width) / 2 | floor),
          ($d.origin.y + ($d.size.height - $height) / 2 | floor),
          $width,
          $height
        ]
      | map(tostring)
      | join(" ")'
)"

osascript - "$pid" $geometry >/dev/null <<'EOF'
on run argv
  set pid to (item 1 of argv) as integer
  tell application "System Events"
    tell (first process whose unix id is pid)
      set position of window 1 to {(item 2 of argv) as integer, (item 3 of argv) as integer}
      set size of window 1 to {(item 4 of argv) as integer, (item 5 of argv) as integer}
    end tell
  end tell
end run
EOF
