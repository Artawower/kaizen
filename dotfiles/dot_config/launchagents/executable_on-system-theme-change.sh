#!/usr/bin/env bash
set -euo pipefail

# Trigger editors/term tools theme switchers
if [ -x "$HOME/.config/scripts/helix-theme-switcher" ]; then
  "$HOME/.config/scripts/helix-theme-switcher" || true
fi
if [ -x "$HOME/.config/zellij/theme_switcher.sh" ]; then
  "$HOME/.config/zellij/theme_switcher.sh" || true
fi

exit 0

