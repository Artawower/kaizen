#!/usr/bin/env python3
import os
import platform
import shutil
import subprocess
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

import tomllib

KAIZEN_DIR = Path(__file__).parent
FEATURES_DIR = KAIZEN_DIR / "features"
DOTFILES_DIR = KAIZEN_DIR / "dotfiles"
CONFIG_FILE = Path.home() / ".config" / "kaizen" / "config.toml"
MISE_CONFIG = Path.home() / ".config" / "mise.toml"

_CAPTURE_PATHS = [
    Path.home() / ".pi" / "agent" / "settings.json",
    Path.home() / ".pi" / "agent" / "mcp.json",
]


class PackageManager(ABC):
    @abstractmethod
    def install(self, packages: dict) -> None: ...

    @abstractmethod
    def update(self) -> None: ...

    def _run(self, cmd: list[str], env: dict | None = None) -> None:
        print(f"  $ {' '.join(cmd)}")
        result = subprocess.run(cmd, env=env or os.environ)
        if result.returncode != 0:
            print(f"  warning: command failed (exit {result.returncode}), continuing")


class Brew(PackageManager):
    def install(self, packages: dict) -> None:
        section = packages.get("macos", {})
        for tap in section.get("taps", []):
            self._run(["brew", "tap", tap])
        brew_args = section.get("brew_args", {})
        for pkg in section.get("brew", []):
            self._run(["brew", "install", "--yes", pkg, *brew_args.get(pkg, [])])
        if casks := section.get("cask", []):
            self._run(["brew", "install", "--yes", "--cask", *casks])

    def update(self) -> None:
        self._run(["brew", "update"])
        self._run(["brew", "upgrade", "--yes"])


class Dnf(PackageManager):
    def install(self, packages: dict) -> None:
        section = packages.get("linux", {})
        if pkgs := section.get("dnf", []):
            self._run(["sudo", "dnf", "install", "-y", *pkgs])
        for app in section.get("flatpak", []):
            self._run(["flatpak", "install", "-y", "flathub", app])

    def update(self) -> None:
        self._run(["sudo", "dnf", "upgrade", "-y"])


class Apt(PackageManager):
    def install(self, packages: dict) -> None:
        section = packages.get("linux", {})
        if pkgs := section.get("apt", []):
            self._run(["sudo", "apt", "install", "-y", *pkgs])
        for app in section.get("flatpak", []):
            self._run(["flatpak", "install", "-y", "flathub", app])

    def update(self) -> None:
        self._run(["sudo", "apt", "update"])
        self._run(["sudo", "apt", "upgrade", "-y"])


_ADAPTERS: dict[str, PackageManager] = {
    "macos": Brew(),
    "fedora": Dnf(),
    "rhel": Dnf(),
    "ubuntu": Apt(),
    "debian": Apt(),
}


def detect_os() -> str:
    if platform.system() == "Darwin":
        return "macos"
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if line.startswith("ID="):
                return line.split("=", 1)[1].strip().strip('"')
    except FileNotFoundError:
        pass
    return "linux"


def adapter_for(os_name: str) -> PackageManager:
    return _ADAPTERS.get(os_name, Dnf())


def load_toml(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"  warning: {path}: {e}")
        return {}


def _mise_key(name: str) -> str:
    return f'"{name}"' if any(c in name for c in (":", "@", "/")) else name


def _write_mise_toml(tools: dict[str, str], dest: Path) -> None:
    lines = ["[tools]"]
    for name, version in tools.items():
        if not isinstance(version, str):
            raise TypeError(f"mise version for {name} must be a string")
        lines.append(f'{_mise_key(name)} = "{version}"')
    dest.write_text("\n".join(lines) + "\n")


@dataclass
class Feature:
    name: str
    variant: str | None = None

    @property
    def label(self) -> str:
        return f"{self.name}/{self.variant}" if self.variant else self.name

    @property
    def packages_file(self) -> Path:
        return FEATURES_DIR / self.name / "packages.toml"

    @property
    def mise_file(self) -> Path:
        return FEATURES_DIR / self.name / "mise.toml"

    @property
    def variant_packages_file(self) -> Path | None:
        if not self.variant:
            return None
        return FEATURES_DIR / self.name / "variants" / self.variant / "packages.toml"

    @property
    def post_install(self) -> Path:
        return FEATURES_DIR / self.name / "post_install.py"


def parse_features(config: dict) -> list[Feature]:
    result = []
    for name, val in config.get("features", {}).items():
        if isinstance(val, bool) and val:
            result.append(Feature(name))
        elif isinstance(val, dict) and val.get("enabled", True):
            result.append(Feature(name, val.get("variant")))
    return result


class Kaizen:
    def __init__(self, config: dict) -> None:
        self._config = config
        self._os = detect_os()
        self._adapter = adapter_for(self._os)

    def sync(self) -> None:
        features = parse_features(self._config)
        print(f"OS: {self._os}\n")
        for feature in features:
            self._install_packages(feature)
        self._generate_mise_config(features)
        if shutil.which("mise"):
            print("[mise]")
            subprocess.run(["mise", "install"], check=True)
            print()
        print("[dotfiles]")
        subprocess.run(["chezmoi", "apply", "--source", str(DOTFILES_DIR)], check=True)

    def update(self) -> None:
        self._adapter.update()
        if shutil.which("mise"):
            subprocess.run(["mise", "upgrade"], check=True)

    def bump(self) -> None:
        subprocess.run(["mise", "upgrade", "--bump", "--interactive"], check=False)
        self._capture_mise_versions(parse_features(self._config))
        self.capture()

    def capture(self) -> None:
        for path in _CAPTURE_PATHS:
            if path.exists():
                subprocess.run(
                    ["chezmoi", "re-add", "--source", str(DOTFILES_DIR), str(path)],
                    check=False,
                )
                print(f"  captured {path}")

    def status(self) -> None:
        print(f"OS      : {self._os}")
        print(f"config  : {CONFIG_FILE}")
        print(
            f"mise    : {MISE_CONFIG} {'(exists)' if MISE_CONFIG.exists() else '(not generated yet)'}"
        )
        print(f"chezmoi : {shutil.which('chezmoi') or 'not found'}")
        print(f"mise    : {shutil.which('mise') or 'not found'}")

    def _install_packages(self, feature: Feature) -> None:
        print(f"[{feature.label}]")
        self._adapter.install(load_toml(feature.packages_file))
        if feature.variant_packages_file:
            self._adapter.install(load_toml(feature.variant_packages_file))
        if feature.post_install.exists():
            subprocess.run(
                [sys.executable, str(feature.post_install), self._os], check=False
            )
        print()

    def _generate_mise_config(self, features: list[Feature]) -> None:
        tools: dict = {}
        for feature in features:
            tools.update(load_toml(feature.mise_file).get("tools", {}))
        if not tools:
            return
        print("[mise config]")
        _write_mise_toml(tools, MISE_CONFIG)
        print(f"  written {MISE_CONFIG}")
        print()

    def _capture_mise_versions(self, features: list[Feature]) -> None:
        live_tools = load_toml(MISE_CONFIG).get("tools", {})
        for feature in features:
            if not feature.mise_file.exists():
                continue
            feature_tools = load_toml(feature.mise_file).get("tools", {})
            updated = {k: live_tools.get(k, v) for k, v in feature_tools.items()}
            if updated != feature_tools:
                _write_mise_toml(updated, feature.mise_file)
                print(f"  updated {feature.mise_file.relative_to(KAIZEN_DIR)}")


_COMMANDS = {"sync", "update", "bump", "capture", "status"}

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sync"
    if cmd not in _COMMANDS:
        print(f"unknown command: {cmd}. available: {', '.join(sorted(_COMMANDS))}")
        sys.exit(1)
    if not CONFIG_FILE.exists():
        print(f"config not found: {CONFIG_FILE}")
        print("copy config.example.toml to ~/.config/kaizen/config.toml")
        sys.exit(1)
    getattr(Kaizen(load_toml(CONFIG_FILE)), cmd)()
