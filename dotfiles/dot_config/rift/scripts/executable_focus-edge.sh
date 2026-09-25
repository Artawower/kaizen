#!/bin/sh
set -eu

direction="${1:?usage: focus-edge.sh left|right}"

case "$direction" in
  left)  fallback="prev" ;;
  right) fallback="next" ;;
  *) echo "direction must be left or right" >&2; exit 2 ;;
esac

# Rift query output exposes active workspace + is_focused/window_server_id.
before="$(
  rift-cli query workspaces |
    jq -r '.[] | select(.is_active == true) | .windows[]? | select(.is_focused == true) | .window_server_id' |
    head -n1
)"

rift-cli execute window focus "$direction" >/dev/null 2>&1 || true

after="$(
  rift-cli query workspaces |
    jq -r '.[] | select(.is_active == true) | .windows[]? | select(.is_focused == true) | .window_server_id' |
    head -n1
)"

# If focus did not change, we were at the horizontal boundary.
if [ -n "$before" ] && [ "$before" = "$after" ]; then
  if [ "$fallback" = "next" ]; then
    rift-cli execute workspace next >/dev/null
  else
    rift-cli execute workspace prev >/dev/null
  fi
fi
