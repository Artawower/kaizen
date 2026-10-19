#!/usr/bin/env bash
# Smart focus — single state read via jq (fast path).
# Usage: focus.sh <left|right|up|down>
set -euo pipefail

direction=${1:?direction required}

state=$(komorebic state 2>/dev/null)

monitor='.monitors.elements[0]'
ws_idx="($monitor.workspaces.focused)"
ws="($monitor.workspaces.elements[$ws_idx])"
container_count="($ws.containers.elements | length)"
focused_idx="($ws.containers.focused)"
focused_c="($ws.containers.elements[$focused_idx])"
stack_size="($focused_c.windows.elements | length)"

info=$(echo "$state" | jq -r "
  [$container_count, $focused_idx, $stack_size] | @csv
" 2>/dev/null) || {
	komorebic focus "$direction"
	exit 0
}

IFS=',' read -r count idx stack_len <<<"$info"

# In stack + horizontal → cycle stack
if ((stack_len > 1)); then
	if [[ "$direction" == "right" ]]; then
		komorebic cycle-stack next
		exit 0
	elif [[ "$direction" == "left" ]]; then
		komorebic cycle-stack previous
		exit 0
	fi
fi

# At edge → cycle workspace
if [[ "$direction" == "left" && "$idx" == "0" ]] ||
	[[ "$direction" == "right" && "$idx" -ge $((count - 1)) ]]; then
	[[ "$direction" == "left" ]] &&
		komorebic cycle-workspace previous ||
		komorebic cycle-workspace next
	exit 0
fi

komorebic focus "$direction"
