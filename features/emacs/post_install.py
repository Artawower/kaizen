#!/usr/bin/env python3
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import tomllib

EMACS_APPLICATION = "Emacs.app"
CLIENT_APPLICATION = "Emacs Client.app"
CLIENT_PLACEHOLDER = "__EMACSCLIENT__"
CLIENT_SOURCE = Path(__file__).with_name("emacs-client.applescript")
PACKAGES_SOURCE = Path(__file__).with_name("packages.toml")


def emacs_formula() -> str:
    with PACKAGES_SOURCE.open("rb") as file:
        packages = tomllib.load(file)
    formulas = [
        package
        for package in packages.get("macos", {}).get("brew", [])
        if package == "emacs-plus" or package.startswith("emacs-plus@")
    ]
    if len(formulas) != 1:
        raise RuntimeError("macOS packages must declare exactly one Emacs Plus formula")
    return formulas[0]


def bundle_version(application: Path) -> str | None:
    info = application / "Contents" / "Info.plist"
    if not info.exists():
        return None
    with info.open("rb") as file:
        return plistlib.load(file).get("CFBundleVersion")


def remove_path(path: Path) -> None:
    try:
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.exists():
            shutil.rmtree(path)
    except OSError as error:
        raise RuntimeError(f"failed to remove {path.name}: {error}") from error


def install_application(source: Path, destination: Path) -> None:
    if bundle_version(source) == bundle_version(destination):
        print(f"  {destination.name} already up to date")
        return
    try:
        remove_path(destination)
        shutil.copytree(source, destination, symlinks=True)
    except OSError as error:
        raise RuntimeError(f"failed to install {destination.name}: {error}") from error
    print(f"  {destination.name} copied to /Applications")


def build_emacs_client(source: Path, destination: Path, emacsclient: Path) -> None:
    launcher = CLIENT_SOURCE.read_text()
    if launcher.count(CLIENT_PLACEHOLDER) != 1:
        raise RuntimeError("invalid Emacs Client launcher template")
    launcher = launcher.replace(CLIENT_PLACEHOLDER, str(emacsclient))
    with tempfile.TemporaryDirectory() as directory:
        build_directory = Path(directory)
        built_application = build_directory / CLIENT_APPLICATION
        launcher_source = build_directory / "main.applescript"
        launcher_source.write_text(launcher)
        shutil.copytree(source, built_application, symlinks=True)
        compiled_script = (
            built_application / "Contents" / "Resources" / "Scripts" / "main.scpt"
        )
        subprocess.run(
            ["osacompile", "-o", str(compiled_script), str(launcher_source)],
            check=True,
        )
        subprocess.run(
            ["codesign", "--force", "--deep", "--sign", "-", str(built_application)],
            check=True,
        )
        subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(built_application)],
            check=True,
        )
        try:
            remove_path(destination)
            shutil.copytree(built_application, destination, symlinks=True)
        except OSError as error:
            raise RuntimeError(
                f"failed to install {destination.name}: {error}"
            ) from error
    print("  Emacs Client launcher rebuilt for the Homebrew daemon")


def main() -> None:
    os_name = sys.argv[1] if len(sys.argv) > 1 else ""
    if os_name != "macos":
        return
    formula = emacs_formula()
    prefix = Path(
        subprocess.run(
            ["brew", "--prefix", formula],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )
    emacs_source = prefix / EMACS_APPLICATION
    client_source = prefix / CLIENT_APPLICATION
    if not emacs_source.exists():
        raise FileNotFoundError(f"application bundle not found: {emacs_source}")
    if not client_source.exists():
        raise FileNotFoundError(f"application bundle not found: {client_source}")
    emacs_destination = Path("/Applications") / EMACS_APPLICATION
    client_destination = Path("/Applications") / CLIENT_APPLICATION
    install_application(emacs_source, emacs_destination)
    build_emacs_client(
        client_source, client_destination, prefix / "bin" / "emacsclient"
    )
    subprocess.run(
        [
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "-f",
            str(emacs_destination),
            str(client_destination),
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
