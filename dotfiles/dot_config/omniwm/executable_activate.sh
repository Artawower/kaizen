#!/bin/sh

if command -v yabai >/dev/null 2>&1; then
	yabai --stop-service >/dev/null 2>&1 || true
fi

pkill -x AeroSpace >/dev/null 2>&1 || true
open -a OmniWM
