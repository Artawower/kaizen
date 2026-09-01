#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

BRANCH = "steel-event-system"
REPOSITORY = "https://github.com/mattwparas/helix.git"
FORGE_PACKAGES = {
    "nrepl-steel": "https://github.com/waddie/nrepl-steel",
    "nrepl.hx": "https://github.com/waddie/nrepl.hx",
    "paredit.hx": "https://github.com/waddie/paredit.hx",
    "moka": "https://github.com/Ra77a3l3-jar/moka.hx.git",
    "scopeline": "https://github.com/Ra77a3l3-jar/scopeline.git",
    "trail": "https://github.com/Ra77a3l3-jar/trail.hx.git",
    "forest": "https://github.com/Ra77a3l3-jar/forest.hx.git",
}
REQUIRED_BINARIES = (
    "hx",
    "steel",
    "steel-language-server",
    "forge",
    "cargo-steel-lib",
)

home = Path.home()
source = home / ".local" / "share" / "kaizen" / "sources" / "helix-steel"
state = home / ".local" / "state" / "kaizen" / "helix-steel-revision"
runtime = home / ".config" / "helix" / "runtime"
cargo_home = Path(os.environ.get("CARGO_HOME", home / ".cargo"))
steel_home = Path(os.environ.get("STEEL_HOME", home / ".local" / "share" / "steel"))


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


def require_executable(name: str) -> str:
    executable = shutil.which(str(cargo_home / "bin" / name)) or shutil.which(name)
    if not executable:
        raise FileNotFoundError(f"executable not found: {name}")
    return executable


def prepare_source(git: str, update: bool) -> str:
    source.parent.mkdir(parents=True, exist_ok=True)
    created = not source.exists()
    changed = created
    if created:
        run([git, "clone", "--depth=1", "--branch", BRANCH, REPOSITORY, str(source)])
    else:
        if not (source / ".git").exists():
            raise RuntimeError(f"Helix source is not a Git checkout: {source}")
        origin = output([git, "remote", "get-url", "origin"], source)
        if origin != REPOSITORY:
            raise RuntimeError(f"unexpected Helix origin: {origin}")
        if update:
            current_revision = output([git, "rev-parse", "HEAD"], source)
            run([git, "fetch", "--depth=1", "origin", BRANCH], source)
            next_revision = output([git, "rev-parse", "FETCH_HEAD"], source)
            changed = current_revision != next_revision
            if changed:
                run([git, "checkout", "--force", "--detach", "FETCH_HEAD"], source)
    if changed:
        run([git, "submodule", "sync", "--recursive"], source)
        run([git, "submodule", "update", "--init", "--recursive", "--depth=1"], source)
    return output([git, "rev-parse", "HEAD"], source)


def needs_build(revision: str) -> bool:
    installed_revision = state.read_text().strip() if state.exists() else ""
    return revision != installed_revision or any(
        not shutil.which(str(cargo_home / "bin" / name)) for name in REQUIRED_BINARIES
    )


def installed_package_revision(git: str, name: str, repository: str) -> str | None:
    package = steel_home / "cogs" / name
    if not (package / ".git").exists():
        return None
    if output([git, "remote", "get-url", "origin"], package) != repository:
        return None
    return output([git, "rev-parse", "HEAD"], package)


def remote_revision(git: str, repository: str) -> str:
    result = output([git, "ls-remote", repository, "HEAD"])
    if not result:
        raise RuntimeError(f"repository has no HEAD revision: {repository}")
    return result.split()[0]


def install_packages(forge: str, git: str, update: bool) -> None:
    for name, repository in FORGE_PACKAGES.items():
        installed_revision = installed_package_revision(git, name, repository)
        if installed_revision and not update:
            continue
        command = [forge, "pkg", "install", "--git", repository, "--force"]
        expected_revision = None
        if update:
            expected_revision = remote_revision(git, repository)
            if installed_revision == expected_revision:
                continue
            command.extend(["--rev", expected_revision])
        run(command)
        actual_revision = installed_package_revision(git, name, repository)
        if not actual_revision or (
            expected_revision and actual_revision != expected_revision
        ):
            raise RuntimeError(f"Forge package installation failed: {name}")


def patch_forest_redraw() -> None:
    path = steel_home / "cogs" / "forest" / "forest.scm"
    contents = path.read_text()
    patched = contents.replace("(helix.redraw '())", "(helix.redraw)")
    if patched != contents:
        path.write_text(patched)


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


def main() -> None:
    action = sys.argv[2] if len(sys.argv) > 2 else "sync"
    if action not in {"sync", "update"}:
        raise ValueError(f"unsupported Helix action: {action}")
    git = require_executable("git")
    cargo = require_executable("cargo")
    revision = prepare_source(git, action == "update")
    if needs_build(revision):
        run([cargo, "xtask", "steel"], source)
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(revision + "\n")
    install_packages(require_executable("forge"), git, action == "update")
    patch_forest_redraw()
    link_runtime()
    print(f"  Helix Steel ready at {revision[:12]}")


if __name__ == "__main__":
    main()
