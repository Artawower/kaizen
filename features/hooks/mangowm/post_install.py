#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path

SUPPORTED_SYSTEMS = {"fedora", "fedora-asahi-remix"}
TERRA_REPOSITORY = "terra,https://repos.fyralabs.com/terra$releasever"
XREMAP_REPOSITORY = "blakegardner/xremap"
PACKAGES = ("mangowm", "noctalia", "satty", "vicinae", "xremap-wlroots")
LEGACY_PACKAGES = ("noctalia-shell", "noctalia-qs")


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def dnf(*arguments: str) -> list[str]:
    return ["sudo", "env", "-u", "LD_LIBRARY_PATH", "dnf", *arguments]


def ensure_terra() -> None:
    if Path("/etc/yum.repos.d/terra.repo").exists():
        return
    run(
        dnf(
            "install",
            "-y",
            "--nogpgcheck",
            "--repofrompath",
            TERRA_REPOSITORY,
            "terra-release",
        )
    )


def install(system: str) -> None:
    if system not in SUPPORTED_SYSTEMS:
        raise RuntimeError(f"MangoWM is unsupported on {system or 'this system'}")
    ensure_terra()
    run(dnf("copr", "enable", "-y", XREMAP_REPOSITORY))
    run(dnf("install", "-y", "--allowerasing", *PACKAGES))
    run(dnf("remove", "-y", *LEGACY_PACKAGES))


def main() -> None:
    install(sys.argv[1] if len(sys.argv) > 1 else "")


if __name__ == "__main__":
    main()
