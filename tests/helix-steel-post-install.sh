#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
POST_INSTALL_PATH="$PROJECT_DIR/features/helix/variants/steel/post_install.py" python3 <<'PY'
import importlib.util
import os
import tempfile
from pathlib import Path

path = Path(os.environ["POST_INSTALL_PATH"])
spec = importlib.util.spec_from_file_location("helix_steel_post_install_test", path)
assert spec and spec.loader
post_install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(post_install)

repository = "https://example.com/sample.git"
post_install.FORGE_PACKAGES = {"sample": repository}
prepare_package_source = post_install.prepare_package_source


def test_sync_skips_installed_package() -> None:
    events: list[object] = []
    post_install.installed_package_revision = lambda *_: "current"
    post_install.prepare_package_source = lambda *_: events.append("prepare")
    post_install.run = lambda *args, **kwargs: events.append((args, kwargs))
    post_install.install_packages("forge", "git", False)
    assert events == []


def test_update_skips_current_package() -> None:
    events: list[object] = []
    post_install.installed_package_revision = lambda *_: "current"
    post_install.prepare_package_source = lambda *_: (
        Path("/tmp/cog-sources/sample"),
        "current",
    )
    post_install.run = lambda *args, **kwargs: events.append((args, kwargs))
    post_install.install_packages("forge", "git", True)
    assert events == []


def test_update_installs_local_package_source() -> None:
    revisions = iter(["old", "new"])
    events: list[object] = []
    source = Path("/tmp/cog-sources/sample")
    post_install.installed_package_revision = lambda *_: next(revisions)
    post_install.prepare_package_source = lambda *_: (source, "new")
    post_install.run = lambda command, cwd=None: events.append((command, cwd))
    post_install.install_packages("forge", "git", True)
    assert events == [(["forge", "install", str(source)], None)]


def test_existing_package_source_fetches_head() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = root / "cog-sources" / "sample"
        (source / ".git").mkdir(parents=True)
        events: list[tuple[list[str], Path | None]] = []
        post_install.steel_home = root
        post_install.run = lambda command, cwd=None: events.append((command, cwd))

        def fake_output(command: list[str], cwd: Path | None = None) -> str:
            if command[1:4] == ["remote", "get-url", "origin"]:
                return repository
            assert command[1:] == ["rev-parse", "FETCH_HEAD"]
            return "new"

        post_install.output = fake_output
        actual_source, revision = prepare_package_source("git", "sample", repository)
        assert actual_source == source
        assert revision == "new"
        assert events == [
            (["git", "fetch", "--depth=1", "origin", "HEAD"], source),
            (["git", "checkout", "--force", "--detach", "new"], source),
        ]


test_sync_skips_installed_package()
test_update_skips_current_package()
test_update_installs_local_package_source()
test_existing_package_source_fetches_head()
print("Helix Steel post-install tests passed")
PY
