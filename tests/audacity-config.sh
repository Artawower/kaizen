#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wrapper="$repo_root/dotfiles/dot_local/bin/executable_audacity"
desktop_template="$repo_root/dotfiles/dot_local/share/applications/audacity.desktop.tmpl"
rendered=$(mktemp --suffix=.desktop)
source_dir=$(mktemp -d)
trap 'rm -f "$rendered"; rmdir "$source_dir"' EXIT

grep -Fxq 'export AU_QT_QPA_PLATFORM=wayland' "$wrapper"
grep -Fxq 'export QT_QPA_PLATFORM=wayland' "$wrapper"
grep -Fq "exec \"\$appimage\" \"\$@\"" "$wrapper"
[[ $(<"$repo_root/dotfiles/dot_local/bin/symlink_audacity4") == audacity ]]
[[ $(<"$repo_root/dotfiles/dot_local/share/applications/symlink_audacity4.desktop") == audacity.desktop ]]

chezmoi execute-template --source "$source_dir" --file "$desktop_template" >"$rendered"
grep -Fq "Exec=$HOME/.local/bin/audacity %F" "$rendered"
grep -Fq "TryExec=$HOME/.local/bin/audacity" "$rendered"

if command -v desktop-file-validate >/dev/null; then
    desktop-file-validate "$rendered"
fi

echo "Audacity config tests passed"
