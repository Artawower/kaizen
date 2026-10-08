#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    echo 'DevCache tests skipped: Linux is required'
    exit 0
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/dotfiles/dot_config/scripts/executable_devcache"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export DEVCACHE_TEST_MODE=1
export DEVCACHE_LOCK_FILE="$tmp/devcache.lock"
export npm_config_cache="$HOME/.npm"
mkdir -p "$HOME/.npm/_cacache/index-v5"

python3 "$script" setup --local-only --dry-run --caches bun,cargo,npm >"$tmp/dry-run.txt"
grep -Fq 'Dry run: no files or system settings changed.' "$tmp/dry-run.txt"
[[ ! -e "$XDG_CONFIG_HOME/devcache/config.toml" ]]

mkdir -p "$HOME/.cargo/registry"
printf 'original cargo cache\n' >"$HOME/.cargo/registry/index.txt"
printf 'existing npm cache\n' >"$HOME/.npm/_cacache/index-v5/entry"
printf 'install.globalDir = "custom"\n' >"$HOME/.bunfig.toml"
python3 "$script" setup --local-only --yes --migrate-existing --caches bun,cargo,npm,pnpm,go,python,pip,uv,mise
[[ ! -e "$XDG_CONFIG_HOME/systemd/user/kaizen-devcache-gc.service" ]]
[[ ! -e "$XDG_CONFIG_HOME/systemd/user/kaizen-devcache-gc.timer" ]]
[[ -f "$XDG_CACHE_HOME/devcache/npm/_cacache/index-v5/entry" ]]
grep -Fq 'existing npm cache' "$HOME/.npm/_cacache/index-v5/entry"
[[ -L "$HOME/.cargo/registry" ]]
[[ $(readlink -f "$HOME/.cargo/registry") == "$XDG_CACHE_HOME/devcache/cargo/registry" ]]
[[ -f "$XDG_STATE_HOME/devcache/backups/cargo/registry/index.txt" ]]
grep -Fq 'install.globalDir = "custom"' "$HOME/.bunfig.toml"
grep -Fq "dir = \"$XDG_CACHE_HOME/devcache/bun\"" "$HOME/.bunfig.toml"
grep -Fq "npm_config_cache=\"$XDG_CACHE_HOME/devcache/npm\"" "$XDG_CONFIG_HOME/environment.d/90-devcache.conf"
grep -Fq "pnpm_config_store_dir=\"$XDG_CACHE_HOME/devcache/pnpm\"" "$XDG_CONFIG_HOME/environment.d/90-devcache.conf"
grep -Fq "\$GOCACHE" "$XDG_CONFIG_HOME/devcache/xonsh.xsh"
if command -v xonsh >/dev/null; then
    xonsh --no-rc -c "source $repo_root/dotfiles/dot_config/xonsh/env.xsh; print(\$GOCACHE)" >"$tmp/xonsh-cache.txt"
    grep -Fxq "$XDG_CACHE_HOME/devcache/go/build" "$tmp/xonsh-cache.txt"
fi
python3 - "$script" <<'PY'
import importlib.machinery, importlib.util, os, subprocess, sys
from pathlib import Path
source = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("devcache", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
with module.operation_lock():
    result = subprocess.run([sys.executable, str(source), "disable", "--yes"], capture_output=True, text=True, env=os.environ.copy())
assert result.returncode != 0
assert "Another devcache operation is in progress" in result.stderr
PY

python3 "$script" status --json >"$tmp/status.json"
python3 - "$tmp/status.json" <<'PY'
import json, sys
status = json.load(open(sys.argv[1]))
assert status["configured"]
assert status["enabled"]
assert status["adapters"]["cargo"]["enabled"]
assert status["adapters"]["dnf5"]["supported"] is False
PY
python3 - "$script" <<'PY'
import importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("devcache", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
config = {"device_uuid": "test-uuid", "filesystem": "btrfs", "root": "/stable/cache"}
valid = [{"target": "/run/media/user/ssd", "uuid": "test-uuid", "fstype": "btrfs", "fsroot": "/", "options": "rw,relatime", "children": [{"target": "/stable/cache", "uuid": "test-uuid", "fstype": "btrfs", "fsroot": "/Kaizen/DevCache", "options": "rw,relatime"}]}]
assert module.has_matching_source_mount(config, valid)
assert module.matching_source_fsroots(config, valid) == ["/Kaizen/DevCache"]
subvolume = [{**valid[0], "fsroot": "/@"}]
assert module.matching_source_fsroots(config, subvolume) == ["/@/Kaizen/DevCache"]
assert not module.has_matching_source_mount(config, [valid[0]["children"][0]])
assert not module.has_matching_source_mount(config, [{**valid[0], "uuid": "other-uuid"}])
assert not module.has_matching_source_mount(config, [{**valid[0], "fstype": "xfs"}])
assert not module.has_matching_source_mount(config, [{**valid[0], "options": "ro,relatime"}])
PY
python3 "$script" doctor >"$tmp/doctor.txt"
grep -Fq 'devcache checks passed.' "$tmp/doctor.txt"

mkdir -p "$XDG_CACHE_HOME/devcache/npm" "$XDG_CACHE_HOME/devcache/bun" "$XDG_CACHE_HOME/devcache/cargo/registry" "$XDG_CACHE_HOME/devcache/python/pycache"
printf 'local npm cache\\n' >"$XDG_CACHE_HOME/devcache/npm/offline"
printf 'bun shared store\\n' >"$XDG_CACHE_HOME/devcache/bun/shared"
printf 'cargo registry\\n' >"$XDG_CACHE_HOME/devcache/cargo/registry/index"
printf 'python bytecode\\n' >"$XDG_CACHE_HOME/devcache/python/pycache/keep"
python3 "$script" gc --auto --dry-run >"$tmp/auto-gc.txt"
grep -Fq 'preserving local fallback' "$tmp/auto-gc.txt"
python3 "$script" gc --auto >"$tmp/auto-gc-run.txt"
[[ -f "$XDG_CACHE_HOME/devcache/npm/offline" ]]
[[ -f "$XDG_CACHE_HOME/devcache/bun/shared" ]]
[[ -f "$XDG_CACHE_HOME/devcache/cargo/registry/index" ]]
python3 "$script" gc --dry-run >"$tmp/gc.txt"
grep -Fq 'preserving local fallback' "$tmp/gc.txt"
[[ -f "$XDG_CACHE_HOME/devcache/python/pycache/keep" ]]
python3 - "$script" "$tmp/gc-fixture" <<'PY'
import importlib.machinery, importlib.util, os, sys
from pathlib import Path
source = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("devcache", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
root = Path(sys.argv[2])
source_cache = root / "source-cache"
destination_cache = root / "destination-cache"
source_cache.mkdir(parents=True)
destination_cache.mkdir(parents=True)
(source_cache / "offline").write_text("source")
(destination_cache / "only-destination").write_text("destination")
assert module.copy_cache_tree_if_absent(source_cache, destination_cache) == (0, 1)
assert (source_cache / "offline").read_text() == "source"
assert (destination_cache / "only-destination").read_text() == "destination"
assert not (destination_cache / "offline").exists()
outside_cache = root / "outside-cache"
outside_cache.mkdir()
(root / "linked-cache").symlink_to(outside_cache, target_is_directory=True)
assert module.safe_managed_cache_path(root, "linked-cache") is None
(root / "linked-parent").symlink_to(outside_cache, target_is_directory=True)
assert module.safe_managed_cache_path(root, "linked-parent/cache") is None
bin_dir = root / "bin"
bin_dir.mkdir(parents=True)
for name in ("npm", "python3", "uv", "go", "mise", "pnpm", "bun", "cargo"):
    tool = bin_dir / name
    tool.write_text("#!/bin/sh\nexit 0\n")
    tool.chmod(0o700)
os.environ["PATH"] = str(bin_dir)
for name in ("npm", "pip", "uv", "mise", "pnpm", "bun", "cargo", "python"):
    (root / name).mkdir(parents=True, exist_ok=True)
    if name in {"npm", "pip", "uv", "mise"}:
        (root / name / "entry").write_text("data")
(root / "go/build").mkdir(parents=True)
(root / "go/build/entry").write_text("data")
config = {"adapters": ["npm", "pip", "uv", "go", "mise", "pnpm", "bun", "cargo", "python"], "auto_gc_max_bytes": 1}
actions, total, skipped = module.automatic_gc_plan(config, root, automatic=False)
assert {action["adapter"] for action in actions} == {"npm", "pip", "uv", "go", "mise"}
assert total > 1
auto_actions, _, _ = module.automatic_gc_plan(config, root, automatic=True)
assert {action["adapter"] for action in auto_actions} == {"npm", "pip", "uv", "go", "mise"}
config["auto_gc_max_bytes"] = 1000
auto_actions, _, _ = module.automatic_gc_plan(config, root, automatic=True)
assert {action["adapter"] for action in auto_actions} == {"mise"}
assert {"pnpm", "bun", "cargo", "python"}.issubset(skipped)
assert total > 1
npm = next(action for action in actions if action["adapter"] == "npm")
assert str(root / "npm") in npm["argv"]
pip = next(action for action in actions if action["adapter"] == "pip")
assert pip["env"]["PIP_CACHE_DIR"] == str(root / "pip")
uv = next(action for action in actions if action["adapter"] == "uv")
assert str(root / "uv") in uv["argv"]
go = next(action for action in actions if action["adapter"] == "go")
assert go["env"]["GOCACHE"] == str(root / "go/build")
mise = next(action for action in actions if action["adapter"] == "mise")
assert mise["env"]["MISE_CACHE_DIR"] == str(root / "mise")
PY

python3 "$script" disable --yes >"$tmp/disable.txt"
python3 "$script" enable --yes >"$tmp/enable.txt"
printf '\nuser_setting = "preserve me"\n' >>"$XDG_CONFIG_HOME/devcache/config.toml"
python3 "$script" uninstall --yes >"$tmp/uninstall.txt"
[[ -f "$XDG_CONFIG_HOME/devcache/config.toml" ]]
grep -Fq 'preserve me' "$XDG_CONFIG_HOME/devcache/config.toml"
[[ ! -e "$XDG_CONFIG_HOME/environment.d/90-devcache.conf" ]]
[[ ! -e "$XDG_CONFIG_HOME/devcache/xonsh.xsh" ]]
[[ ! -e "$XDG_CONFIG_HOME/systemd/user/kaizen-devcache-gc.service" ]]
[[ ! -e "$XDG_CONFIG_HOME/systemd/user/kaizen-devcache-gc.timer" ]]
[[ -f "$HOME/.cargo/registry/index.txt" ]]
grep -Fq 'original cargo cache' "$HOME/.cargo/registry/index.txt"
grep -Fq 'install.globalDir = "custom"' "$HOME/.bunfig.toml"
[[ -f "$XDG_CACHE_HOME/devcache/bun/shared" ]]

mkdir -p "$tmp/user-edits/home/.config"
HOME="$tmp/user-edits/home" XDG_CONFIG_HOME="$tmp/user-edits/home/.config" XDG_STATE_HOME="$tmp/user-edits/home/.local/state" XDG_CACHE_HOME="$tmp/user-edits/home/.cache" DEVCACHE_TEST_MODE=1 DEVCACHE_LOCK_FILE="$tmp/user-edits.lock" python3 "$script" setup --local-only --yes --caches npm >"$tmp/user-edits-setup.txt"
printf '\nUSER_SETTING=keep\n' >>"$tmp/user-edits/home/.config/environment.d/90-devcache.conf"
printf '\nUSER_SETTING = "keep"\n' >>"$tmp/user-edits/home/.config/devcache/xonsh.xsh"
printf '\nuser_setting = "keep"\n' >>"$tmp/user-edits/home/.config/devcache/config.toml"
HOME="$tmp/user-edits/home" XDG_CONFIG_HOME="$tmp/user-edits/home/.config" XDG_STATE_HOME="$tmp/user-edits/home/.local/state" XDG_CACHE_HOME="$tmp/user-edits/home/.cache" DEVCACHE_TEST_MODE=1 DEVCACHE_LOCK_FILE="$tmp/user-edits.lock" python3 "$script" uninstall --yes >"$tmp/user-edits-uninstall.txt"
grep -Fq 'USER_SETTING=keep' "$tmp/user-edits/home/.config/environment.d/90-devcache.conf"
grep -Fq 'USER_SETTING = "keep"' "$tmp/user-edits/home/.config/devcache/xonsh.xsh"
grep -Fq 'user_setting = "keep"' "$tmp/user-edits/home/.config/devcache/config.toml"

HOME="$tmp/cargo-fallback/home" XDG_CONFIG_HOME="$tmp/cargo-fallback/home/.config" XDG_STATE_HOME="$tmp/cargo-fallback/home/.local/state" XDG_CACHE_HOME="$tmp/cargo-fallback/home/.cache" DEVCACHE_TEST_MODE=1 python3 - "$script" <<'PY'
import importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("devcache", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
paths = module.user_paths()
root = paths["root"]
local = paths["local"]
root.mkdir(parents=True)
local.mkdir(parents=True)
source = paths["home"] / ".cargo/registry/index"
source.mkdir(parents=True)
(source / "offline").write_text("cargo offline data")
module.cargo_cache_links(root, local)
assert (paths["home"] / ".cargo/registry").is_symlink()
assert (root / "cargo/registry/index/offline").read_text() == "cargo offline data"
assert (local / "cargo/registry/index/offline").read_text() == "cargo offline data"
assert (paths["state"] / "backups/cargo/registry/index/offline").read_text() == "cargo offline data"
PY

HOME="$tmp/rollback/home" XDG_CONFIG_HOME="$tmp/rollback/home/.config" XDG_STATE_HOME="$tmp/rollback/home/.local/state" XDG_CACHE_HOME="$tmp/rollback/home/.cache" DEVCACHE_TEST_MODE=1 python3 - "$script" <<'PY'
import importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("devcache", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
paths = module.user_paths()
config = {"version": 2, "enabled": True, "external_enabled": False, "root": str(paths["root"]), "local": str(paths["root"]), "adapters": ["npm"], "previous_environment": {}, "managed_variables": []}
write = module.atomic_write
def fail_xonsh(path, content, mode=0o600):
    if Path(path) == paths["xonsh"]:
        raise OSError("injected Xonsh write failure")
    write(path, content, mode)
module.atomic_write = fail_xonsh
try:
    module.write_environment(config, paths["root"])
except OSError as error:
    assert "injected" in str(error)
else:
    raise AssertionError("injected write failure was not raised")
assert not (paths["environment"] / "90-devcache.conf").exists()
assert not paths["xonsh"].exists()
assert not paths["config"].exists()
PY

HOME="$tmp/setup-rollback/home" XDG_CONFIG_HOME="$tmp/setup-rollback/home/.config" XDG_STATE_HOME="$tmp/setup-rollback/home/.local/state" XDG_CACHE_HOME="$tmp/setup-rollback/home/.cache" DEVCACHE_TEST_MODE=1 python3 - "$script" <<'PY'
import argparse, importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("devcache", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
paths = module.user_paths()
paths["home"].mkdir(parents=True)
mount = paths["home"] / "ssd-mount"
mount.mkdir()
device = {"uuid": "12345678-1234-1234-1234-123456789abc", "filesystem": "btrfs", "mountpoints": [str(mount)]}
module.available_devices = lambda: [device]
module.device_mountpoint = lambda _: mount
module.filesystem_id = lambda _: "same-filesystem"
module.active_users = lambda _: []
module.is_mountpoint = lambda _: False
module.remove_system = lambda _: None
module.activate_system = lambda _: (_ for _ in ()).throw(RuntimeError("injected activation failure"))
def install(config):
    config["system_hashes"] = {"fake": "hash"}
    module.write_config(config)
module.install_system = install
args = argparse.Namespace(local_only=False, device_uuid=device["uuid"], caches="npm", migrate_existing=False, yes=True, dry_run=False)
try:
    module.setup(args)
except RuntimeError as error:
    assert "injected activation failure" in str(error)
else:
    raise AssertionError("injected activation failure was not raised")
config = module.load_config()
assert config["enabled"] is False
assert config["external_enabled"] is True
assert f'npm_config_cache="{config["local"]}/npm"' in (paths["environment"] / config["environment_file"]).read_text()

second = paths["home"].parent / "install-failure"
second.mkdir()
module.os.environ.update({"HOME": str(second), "XDG_CONFIG_HOME": str(second / ".config"), "XDG_STATE_HOME": str(second / ".local/state"), "XDG_CACHE_HOME": str(second / ".cache")})
module.available_devices = lambda: [device]
module.device_mountpoint = lambda _: mount
module.filesystem_id = lambda _: "same-filesystem"
module.active_users = lambda _: []
module.is_mountpoint = lambda _: False
module.install_system = lambda _: (_ for _ in ()).throw(RuntimeError("injected install failure"))
second_paths = module.user_paths()
try:
    module.setup(args)
except RuntimeError as error:
    assert "injected install failure" in str(error)
else:
    raise AssertionError("injected install failure was not raised")
assert not second_paths["config"].exists()
assert not (second_paths["environment"] / "90-devcache.conf").exists()
PY

mkdir -p "$tmp/env-conflict/home/.config/environment.d"
printf 'KEEP_ME=1\n' >"$tmp/env-conflict/home/.config/environment.d/90-devcache.conf"
if HOME="$tmp/env-conflict/home" XDG_CONFIG_HOME="$tmp/env-conflict/home/.config" XDG_STATE_HOME="$tmp/env-conflict/home/.local/state" XDG_CACHE_HOME="$tmp/env-conflict/home/.cache" DEVCACHE_TEST_MODE=1 DEVCACHE_LOCK_FILE="$tmp/env-conflict.lock" python3 "$script" setup --local-only --yes --caches npm >"$tmp/env-conflict.log" 2>&1; then
    echo 'DevCache overwrote a pre-existing environment file' >&2
    exit 1
fi
grep -Fq 'KEEP_ME=1' "$tmp/env-conflict/home/.config/environment.d/90-devcache.conf"
[[ ! -e "$tmp/env-conflict/home/.config/devcache/config.toml" ]]
[[ ! -e "$tmp/env-conflict/home/.config/devcache/xonsh.xsh" ]]

mkdir -p "$tmp/bun-conflict/home/.config"
printf '[install.cache]\ndir = "/custom/cache"\n' >"$tmp/bun-conflict/home/.bunfig.toml"
if HOME="$tmp/bun-conflict/home" XDG_CONFIG_HOME="$tmp/bun-conflict/home/.config" XDG_STATE_HOME="$tmp/bun-conflict/home/.local/state" XDG_CACHE_HOME="$tmp/bun-conflict/home/.cache" DEVCACHE_TEST_MODE=1 DEVCACHE_LOCK_FILE="$tmp/bun-conflict.lock" python3 "$script" setup --local-only --yes --caches bun >"$tmp/bun-conflict.log" 2>&1; then
    echo 'DevCache overwrote a custom Bun cache path' >&2
    exit 1
fi
[[ ! -e "$tmp/bun-conflict/home/.config/environment.d/90-devcache.conf" ]]
grep -Fq 'dir = "/custom/cache"' "$tmp/bun-conflict/home/.bunfig.toml"

mkdir -p "$tmp/source" "$tmp/destination"
printf 'new\n' >"$tmp/source/new.txt"
printf 'source\n' >"$tmp/source/conflict.txt"
printf 'destination\n' >"$tmp/destination/conflict.txt"
python3 - "$script" "$tmp/source" "$tmp/destination" <<'PY'
import importlib.machinery, importlib.util, sys
from pathlib import Path
source = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("devcache", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
copied, skipped = module.copy_missing_tree(sys.argv[2], sys.argv[3])
assert copied == 1 and skipped == 1
assert (Path(sys.argv[3]) / "new.txt").read_text() == "new\n"
assert (Path(sys.argv[3]) / "conflict.txt").read_text() == "destination\n"
outside = Path(sys.argv[3]).parent / "outside"
outside.mkdir()
(Path(sys.argv[3]) / "escape").symlink_to(outside, target_is_directory=True)
(Path(sys.argv[2]) / "escape").mkdir()
(Path(sys.argv[2]) / "escape" / "marker").write_text("safe")
try:
    module.copy_missing_tree(sys.argv[2], sys.argv[3])
except RuntimeError:
    pass
else:
    raise AssertionError("copy followed a destination symlink")
assert not (outside / "marker").exists()
proc_root = Path(sys.argv[3]).parent / "proc-fixtures"
for name, argv in (("cargo", ["cargo", "build", "--release"]), ("bun", ["bun", "install"])):
    proc = proc_root / name
    proc.mkdir(parents=True)
    (proc / "comm").write_text(name)
    (proc / "cmdline").write_bytes(b"\0".join(value.encode() for value in argv) + b"\0")
    assert module.is_cache_operation(proc), f"failed to detect {name} operation"
PY

if command -v systemd-analyze >/dev/null && command -v systemd-escape >/dev/null; then
    mkdir -p "$tmp/units"
    python3 - "$script" "$tmp/units" <<'PY'
import importlib.machinery, importlib.util, os, subprocess, sys
from pathlib import Path
home = Path(sys.argv[2]).parent / "home with spaces ' $ % ; \\ special"
home.mkdir()
os.environ.update({"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "XDG_CACHE_HOME": str(home / ".cache"), "XDG_STATE_HOME": str(home / ".local/state")})
source = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("devcache", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
config = {"device_uuid": "12345678-1234-1234-1234-123456789abc", "filesystem": "btrfs", "external_subdir": "Kaizen/DevCache", "root": str(module.user_paths()["root"]), "local": str(module.user_paths()["local"])}
rendered_config = module.render_system_config(config)
assert rendered_config.endswith("\n")
assert r"\n" not in rendered_config
assert len(rendered_config.splitlines()) == 7
config_path = Path(sys.argv[2]) / "root-helper.conf"
config_path.write_text(rendered_config)
subprocess.run(["bash", "-c", 'source "$1"; [[ "$CACHE_ROOT" == "$2" && "$LOCAL_ROOT" == "$3" && "$DEVICE_FS" == btrfs ]]', "devcache-config-test", str(config_path), config["root"], config["local"]], check=True)
mount_name, mount_text = next((name, text) for name, text in module.system_files(config).items() if name.endswith(".mount"))
assert r"\x20" in mount_name and f"Where={config['root'].replace('%', '%%')}" in mount_text
exec_arg = module.systemd_exec_arg('/path/$value with % "quotes')
assert "$$value" in exec_arg and "%%" in exec_arg and r'\"' in exec_arg
paths = []
for name, content in module.system_files(config).items():
    path = Path(sys.argv[2]) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if path.suffix in {".mount", ".service", ".timer"}:
        paths.append(str(path))
for name, content in module.maintenance_files(config).items():
    path = Path(sys.argv[2]) / "user" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    paths.append(str(path))
subprocess.run(["systemd-analyze", "verify", *paths], check=True)
if module.shutil.which("systemd-tmpfiles"):
    tmpfiles_path = next(Path(sys.argv[2]) / name for name in module.system_files(config) if name.startswith("tmpfiles/"))
    subprocess.run(["systemd-tmpfiles", "--create", "--dry-run", str(tmpfiles_path)], check=True, capture_output=True, text=True)
units = [Path(path).read_text() for path in paths]
assert all("ExecStart=/usr/bin/flock" not in text or "/usr/libexec/kaizen-devcache-mount" in text for text in units)
assert all("/usr/bin/python3" not in text for text in units)
all_files = module.system_files(config)
assert all(content.endswith("\n") for content in all_files.values())
rule = all_files[next(name for name in all_files if name.startswith("udev/"))]
assert rule.endswith("\n") and r"\n" not in rule
assert "UDISKS_IGNORE" not in rule
assert "DEVICE_FS=btrfs\n" in all_files[f"etc/kaizen-devcache/{os.getuid()}.conf"]
assert "CACHE_ROOT=" in all_files[f"etc/kaizen-devcache/{os.getuid()}.conf"]
assert "CACHE_ROOT=" not in "\n".join(text for name, text in all_files.items() if name.startswith("systemd/"))
assert all("ExecStartPre=/usr/libexec/kaizen-devcache-mount" not in text for name, text in all_files.items() if name.endswith(".service"))
lock_rule = all_files[f"tmpfiles/kaizen-devcache-{os.getuid()}.conf"]
assert lock_rule == f"f /run/lock/kaizen-devcache-{os.getuid()}.lock 0660 root {os.getgid()} -\n"
maintenance_config = {**config, "external_enabled": True, "maintenance_hashes": {}}
maintenance = module.maintenance_files(maintenance_config)
maintenance_directory = module.user_paths()["config_home"] / "systemd/user"
maintenance_directory.mkdir(parents=True, exist_ok=True)
for name, content in maintenance.items():
    unit_path = maintenance_directory / name
    unit_path.write_text(content)
    maintenance_config["maintenance_hashes"][name] = module.file_hash(unit_path)
service_name = module.maintenance_unit_names()[0]
service_path = maintenance_directory / service_name
service_path.write_text("[Service]\nExecStart=/bin/true\n")
module.remove_user_maintenance(maintenance_config, persist=False)
assert service_path.read_text() == "[Service]\nExecStart=/bin/true\n"
assert not (maintenance_directory / module.maintenance_unit_names()[1]).exists()
PY
fi

echo 'DevCache tests passed'
