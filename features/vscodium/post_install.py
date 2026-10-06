#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
from pathlib import Path

EXTENSIONS_FILE = (
    Path(__file__).resolve().parents[2]
    / "dotfiles"
    / ".chezmoitemplates"
    / "vscodium"
    / "extensions.json"
)


def load_recommendations() -> list[str]:
    if not EXTENSIONS_FILE.exists():
        return []
    with EXTENSIONS_FILE.open("r", encoding="utf-8") as file:
        data = json.load(file)
    recommendations = data.get("recommendations", [])
    if isinstance(recommendations, list):
        return [str(item) for item in recommendations]
    return []


def resolve_codium_runner(os_name: str) -> list[str] | None:
    for candidate in ("codium", "vscodium"):
        if shutil.which(candidate):
            return [candidate]

    if os_name == "macos":
        app_binary = Path("/Applications/VSCodium.app/Contents/Resources/app/bin/codium")
        if app_binary.is_file():
            return [str(app_binary)]

    if os_name == "linux" and shutil.which("flatpak"):
        probe = subprocess.run(
            ["flatpak", "info", "com.vscodium.codium"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if probe.returncode == 0:
            return ["flatpak", "run", "com.vscodium.codium"]

    return None


def installed_extensions(runner: list[str]) -> set[str]:
    process = subprocess.run(
        [*runner, "--list-extensions"],
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode != 0:
        return set()
    return {line.strip().lower() for line in process.stdout.splitlines() if line.strip()}


def install_extensions(os_name: str) -> None:
    runner = resolve_codium_runner(os_name)
    if not runner:
        return

    extensions = load_recommendations()
    if not extensions:
        return

    installed = installed_extensions(runner)
    for extension in extensions:
        if extension.lower() in installed:
            continue
        print(f"  installing vscodium extension: {extension}")
        subprocess.run(
            [*runner, "--install-extension", extension],
            check=False,
        )


def main() -> None:
    os_name = sys.argv[1] if len(sys.argv) > 1 else "linux"
    install_extensions(os_name)


if __name__ == "__main__":
    main()
