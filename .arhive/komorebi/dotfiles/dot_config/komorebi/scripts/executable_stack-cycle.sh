#!/usr/bin/env bash
# Smart n/e: cycle-stack if in stack, otherwise focus up/down.
# Usage: stack-cycle.sh <next|previous>
set -euo pipefail

dir=${1:?direction required: next|previous}

state=$(komorebic state 2>/dev/null)

monitor='.monitors.elements[0]'
ws_idx="($monitor.workspaces.focused)"
ws="($monitor.workspaces.elements[$ws_idx])"
focused_idx="($ws.containers.focused)"
focused_c="($ws.containers.elements[$focused_idx])"

stack_len=$(echo "$state" | jq -r "($focused_c.windows.elements | length)" 2>/dev/null) || stack_len=1

if (( stack_len > 1 )); then
    komorebic cycle-stack "$dir"
else
    [[ "$dir" == "next" ]] && komorebic focus down || komorebic focus up
fi
