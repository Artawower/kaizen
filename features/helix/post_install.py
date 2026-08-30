#!/usr/bin/env python3
import shutil
import subprocess
import sys
from pathlib import Path

BRANCH = "steel-event-system"
REPOSITORY = "https://github.com/mattwparas/helix.git"
PACKAGES = (
    "https://github.com/waddie/nrepl-steel",
    "https://github.com/waddie/nrepl.hx",
    "https://github.com/waddie/paredit.hx",
)

home = Path.home()
source = home / ".local" / "share" / "kaizen" / "sources" / "helix-steel"
state = home / ".local" / "state" / "kaizen" / "helix-steel-revision"
runtime = home / ".config" / "helix" / "runtime"
binaries = tuple(
    home / ".cargo" / "bin" / name
    for name in (
        "hx",
        "steel",
        "steel-language-server",
        "forge",
        "cargo-steel-lib",
    )
)
package_dirs = tuple(
    home / ".local" / "share" / "steel" / "cogs" / name
    for name in ("nrepl-steel", "nrepl.hx", "paredit.hx")
)


def run(command: list[str], cwd: Path | None = None) -> None:
    subprocess.run(command, cwd=cwd, check=True)


def output(command: list[str], cwd: Path | None = None) -> str:
    return subprocess.run(
        command,
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def update_source(git: str) -> str:
    source.parent.mkdir(parents=True, exist_ok=True)
    if source.exists():
        run([git, "fetch", "--depth=1", "origin", BRANCH], source)
        run([git, "checkout", "--force", "--detach", "FETCH_HEAD"], source)
    else:
        run(
            [
                git,
                "clone",
                "--depth=1",
                "--branch",
                BRANCH,
                "--recurse-submodules",
                REPOSITORY,
                str(source),
            ]
        )
    run([git, "submodule", "sync", "--recursive"], source)
    run([git, "submodule", "update", "--init", "--recursive", "--depth=1"], source)
    return output([git, "rev-parse", "HEAD"], source)


def install_packages(forge: str) -> None:
    for package in PACKAGES:
        run([forge, "pkg", "install", "--git", package, "--force"])


def link_runtime() -> None:
    target = source / "runtime"
    runtime.parent.mkdir(parents=True, exist_ok=True)
    if runtime.is_symlink():
        if runtime.resolve() == target.resolve():
            return
        runtime.unlink()
    elif runtime.exists():
        backup = runtime.with_name("runtime.pre-kaizen")
        if backup.exists():
            raise FileExistsError(f"runtime backup already exists: {backup}")
        runtime.rename(backup)
    runtime.symlink_to(target, target_is_directory=True)


git = shutil.which("git")
cargo = shutil.which("cargo")
if not git or not cargo:
    sys.exit("git and cargo must be available")

revision = update_source(git)
installed_revision = state.read_text().strip() if state.exists() else ""
needs_build = revision != installed_revision or any(
    not path.exists() for path in binaries
)
if needs_build:
    run([cargo, "xtask", "steel"], source)

forge = shutil.which("forge") or str(home / ".cargo" / "bin" / "forge")
if needs_build or any(not path.exists() for path in package_dirs):
    install_packages(forge)

link_runtime()
state.parent.mkdir(parents=True, exist_ok=True)
state.write_text(revision + "\n")
print(f"  Helix Steel ready at {revision[:12]}")
