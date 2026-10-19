#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir "$tmp_dir/source"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$tmp_dir/source/"
cp "$repo_root/dotfiles/.chezmoiignore.tmpl" "$tmp_dir/source/"

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
command = [
    "chezmoi", "--config", str(config), "--source", str(source),
    "--destination", str(destination), "--persistent-state", str(root / "state/chezmoi.db"),
    "--cache", str(root / "cache"), "--no-tty",
]
for os_name in ("darwin", "linux"):
    rendered = subprocess.check_output([
        *command, "execute-template", "--override-data", json.dumps({"chezmoi": {"os": os_name}}),
        "--file", str(source / ".chezmoiignore.tmpl"),
    ], text=True)
    patterns = set(rendered.splitlines())
    common = (".pi/", ".omp/", ".agents/", ".emacs.d/", ".config/ghostty/", ".config/helix/", ".config/nvim/")
    assert not set(common) & patterns, (os_name, set(common) & patterns)
    for path in ("Library/", ".config/skhd/", ".config/aerospace/", ".config/karabiner/", ".config/rift/"):
        assert (path in patterns) == (os_name == "linux"), (os_name, path)
    for path in (".config/mango/", ".config/niri/", ".config/xremap/", ".config/VSCodium/", ".local/bin/audacity"):
        assert (path in patterns) == (os_name == "darwin"), (os_name, path)

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
printf 'Chezmoi platform and generated-file ignore tests passed\n'
