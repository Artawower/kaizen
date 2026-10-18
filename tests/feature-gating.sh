#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir "$tmp_dir/source"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$tmp_dir/source/"
cp "$repo_root/dotfiles/.chezmoiignore.tmpl" "$tmp_dir/source/"

for os in darwin linux; do
    for enabled in true false; do
        chezmoi execute-template \
            --source "$tmp_dir/source" \
            --override-data "{\"chezmoi\":{\"os\":\"$os\"},\"features\":{\"ai\":$enabled,\"emacs\":$enabled,\"terminal\":$enabled,\"keyboard\":$enabled,\"helix\":$enabled,\"tiling\":$enabled,\"neovim\":$enabled,\"vscodium\":$enabled},\"tiling\":{\"variant\":\"aerospace\"}}" \
            --file "$tmp_dir/source/.chezmoiignore.tmpl" >"$tmp_dir/ignore"
        python3 - "$tmp_dir/ignore" "$os" "$enabled" <<'PY'
import sys
from pathlib import Path

ignored = set(Path(sys.argv[1]).read_text().splitlines())
os_name, enabled = sys.argv[2], sys.argv[3] == "true"
common = (
    ".pi/", ".omp/", ".agents/", ".config/opencode/", ".config/eca/",
    ".emacs.d/", ".config/ghostty/", ".config/xonsh/", ".config/nushell/",
    ".config/helix/", ".config/nvim/",
)
for path in common:
    assert (path in ignored) == (not enabled), (os_name, enabled, path)
platform_paths = (
    (".config/aerospace/", ".config/karabiner/", "Library/Application Support/VSCodium/")
    if os_name == "darwin"
    else (".config/VSCodium/", ".var/app/com.vscodium.codium/", ".config/xremap/")
)
for path in platform_paths:
    assert (path in ignored) == (not enabled), (os_name, enabled, path)
PY
    done
done
python3 - "$tmp_dir" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
source = root / "source"
destination = root / "home"
config = root / "config/chezmoi.toml"
config.parent.mkdir()
config.write_text("")
ignored = (
    ".DS_Store", ".config/.DS_Store", "runtime.log", ".config/herdr/herdr-server.log",
    ".config/herdr/session.json", ".config/mise.lock", ".config/nvim/nvim-pack-lock.json",
    ".config/nvim_old/init.lua", ".emacs.d/elpaca/builds/cache.el", ".emacs.d/elpaca.lock",
    ".omp/agent/config.yml.lock", ".agents/.skill-lock.json", "skills-lock.json",
    ".config/scripts/__pycache__/cached.pyc", ".config/scripts/cached.pyo",
    ".config/.pytest_cache/state", ".config/.ruff_cache/state",
)
kept = (
    ".config/nvim/init.lua", ".omp/agent/config.yml", ".agents/skills/example/package-lock.json",
)
for name in (*ignored, *kept):
    path = destination / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("fixture\n")
command = [
    "chezmoi", "--config", str(config), "--source", str(source),
    "--destination", str(destination), "--persistent-state", str(root / "state/chezmoi.db"),
    "--cache", str(root / "cache"), "--no-tty", "--override-data",
    json.dumps({"features": {"ai": True, "emacs": True, "neovim": True}}),
]
result = subprocess.run(
    [*command, "add", *map(str, sorted(destination.iterdir()))],
    capture_output=True, text=True, check=False,
)
assert result.returncode == 0, result.stderr
managed = set(subprocess.check_output([*command, "managed"], text=True).splitlines())
assert not set(ignored) & managed, set(ignored) & managed
assert set(kept) <= managed, set(kept) - managed
assert not (source / "dot_config/herdr/session.json").exists()
assert not (source / "dot_config/nvim/nvim-pack-lock.json").exists()
(source / "dot_config/nvim/nvim-pack-lock.json").write_text("regenerated\n")
managed = set(subprocess.check_output([*command, "managed"], text=True).splitlines())
assert ".config/nvim/nvim-pack-lock.json" not in managed
PY
printf 'Feature gating and generated-file ignore tests passed\n'
