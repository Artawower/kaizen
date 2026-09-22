#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
POST_INSTALL_PATH="$PROJECT_DIR/features/tiling/variants/mangowm/post_install.py" python3 <<'PY'
import importlib.util
import os
from pathlib import Path

path = Path(os.environ["POST_INSTALL_PATH"])
spec = importlib.util.spec_from_file_location("mangowm_post_install_test", path)
assert spec and spec.loader
post_install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(post_install)


def test_install_uses_terra_packages() -> None:
    events: list[object] = []
    post_install.ensure_terra = lambda: events.append("terra")
    post_install.run = events.append
    post_install.install("fedora-asahi-remix")
    assert events == [
        "terra",
        [
            "sudo",
            "env",
            "-u",
            "LD_LIBRARY_PATH",
            "dnf",
            "copr",
            "enable",
            "-y",
            "blakegardner/xremap",
        ],
        [
            "sudo",
            "env",
            "-u",
            "LD_LIBRARY_PATH",
            "dnf",
            "install",
            "-y",
            "--allowerasing",
            "mangowm",
            "noctalia",
            "satty",
            "vicinae",
            "xremap-wlroots",
        ],
        [
            "sudo",
            "env",
            "-u",
            "LD_LIBRARY_PATH",
            "dnf",
            "remove",
            "-y",
            "noctalia-shell",
            "noctalia-qs",
        ],
    ]


def test_missing_terra_bootstraps_repository() -> None:
    events: list[list[str]] = []
    original_exists = Path.exists
    Path.exists = lambda self: False
    post_install.run = events.append
    post_install.ensure_terra()
    Path.exists = original_exists
    assert events == [[
        "sudo",
        "env",
        "-u",
        "LD_LIBRARY_PATH",
        "dnf",
        "install",
        "-y",
        "--nogpgcheck",
        "--repofrompath",
        "terra,https://repos.fyralabs.com/terra$releasever",
        "terra-release",
    ]]


def test_unsupported_system_fails() -> None:
    try:
        post_install.install("ubuntu")
    except RuntimeError as error:
        assert str(error) == "MangoWM is unsupported on ubuntu"
    else:
        raise AssertionError("unsupported system was accepted")


test_missing_terra_bootstraps_repository()
test_install_uses_terra_packages()
test_unsupported_system_fails()
print("MangoWM post-install tests passed")
PY
