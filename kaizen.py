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
DEFAULTS_FILE = DOTFILES_DIR / ".chezmoidata.toml"
USER_DATA_FILE = DOTFILES_DIR / ".chezmoidata" / "99-user.toml"
MISE_CONFIG = Path.home() / ".config" / "mise.toml"

_CAPTURE_PATHS = [
    Path.home() / ".pi" / "agent" / "settings.json",
    Path.home() / ".pi" / "agent" / "mcp.json",
]
_VARIANT_FILES = ("packages.toml", "mise.toml", "post_install.py")


class PackageManager(ABC):
    @abstractmethod
    def install(self, packages: dict) -> None:
        raise NotImplementedError

    @abstractmethod
    def update(self) -> None:
        raise NotImplementedError

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
        return "linux"
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


def read_toml(path: Path) -> dict:
    try:
        with open(path, "rb") as file:
            return tomllib.load(file)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"{path}: {error}") from error


def merge_config(defaults: dict, overrides: dict) -> dict:
    merged = defaults.copy()
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_config(merged[key], value)
        else:
            merged[key] = value
    return merged


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
    def directory(self) -> Path:
        return FEATURES_DIR / self.name

    @property
    def variant_directory(self) -> Path | None:
        if not self.variant:
            return None
        return self.directory / "variants" / self.variant

    @property
    def label(self) -> str:
        return f"{self.name}/{self.variant}" if self.variant else self.name

    @property
    def packages_file(self) -> Path:
        return self.directory / "packages.toml"

    @property
    def mise_file(self) -> Path:
        return self.directory / "mise.toml"

    @property
    def variant_packages_file(self) -> Path | None:
        if not self.variant_directory:
            return None
        return self.variant_directory / "packages.toml"

    @property
    def post_install(self) -> Path:
        return self.directory / "post_install.py"

    @property
    def variant_mise_file(self) -> Path | None:
        if not self.variant_directory:
            return None
        return self.variant_directory / "mise.toml"

    @property
    def variant_post_install(self) -> Path | None:
        if not self.variant_directory:
            return None
        return self.variant_directory / "post_install.py"


def parse_features(config: dict) -> list[Feature]:
    configured = config.get("features", {})
    if not isinstance(configured, dict):
        raise TypeError("features must be a table")
    available = {path.name for path in FEATURES_DIR.iterdir() if path.is_dir()}
    unknown = sorted(set(configured) - available)
    if unknown:
        raise ValueError(f"unknown features: {', '.join(unknown)}")
    result = []
    for name, enabled in configured.items():
        if not isinstance(enabled, bool):
            raise TypeError(f"feature {name} must be true or false")
        if not enabled:
            continue
        settings = config.get(name, {})
        if not isinstance(settings, dict):
            raise TypeError(f"settings for {name} must be a table")
        variant = settings.get("variant")
        if variant is not None and not isinstance(variant, str):
            raise TypeError(f"variant for {name} must be a string")
        feature = Feature(name, variant)
        variants_directory = feature.directory / "variants"
        available_variants = (
            {
                path.name
                for path in variants_directory.iterdir()
                if path.is_dir()
                and any((path / filename).exists() for filename in _VARIANT_FILES)
            }
            if variants_directory.exists()
            else set()
        )
        if available_variants and not variant:
            raise ValueError(f"feature {name} requires a variant")
        if variant and variant not in available_variants:
            raise ValueError(f"unknown variant: {feature.label}")
        result.append(feature)
    return result


class Kaizen:
    def __init__(self, config: dict) -> None:
        self._config = config
        self._os = detect_os()
        self._adapter = adapter_for(self._os)

    def sync(self) -> None:
        features = parse_features(self._config)
        self._write_user_data()
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
        features = parse_features(self._config)
        print(f"OS       : {self._os}")
        print(f"config   : {CONFIG_FILE}")
        print(f"features : {', '.join(feature.label for feature in features)}")
        print(
            f"mise     : {MISE_CONFIG} {'(exists)' if MISE_CONFIG.exists() else '(not generated yet)'}"
        )
        print(f"chezmoi  : {shutil.which('chezmoi') or 'not found'}")
        print(f"mise     : {shutil.which('mise') or 'not found'}")

    def _write_user_data(self) -> None:
        USER_DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
        if USER_DATA_FILE.is_symlink() or USER_DATA_FILE.exists():
            USER_DATA_FILE.unlink()
        USER_DATA_FILE.symlink_to(CONFIG_FILE)

    def _install_packages(self, feature: Feature) -> None:
        print(f"[{feature.label}]")
        self._adapter.install(load_toml(feature.packages_file))
        if feature.variant_packages_file:
            self._adapter.install(load_toml(feature.variant_packages_file))
        if feature.post_install.exists():
            subprocess.run(
                [sys.executable, str(feature.post_install), self._os], check=False
            )
        if feature.variant_post_install and feature.variant_post_install.exists():
            subprocess.run(
                [sys.executable, str(feature.variant_post_install), self._os],
                check=False,
            )
        print()

    def _generate_mise_config(self, features: list[Feature]) -> None:
        tools: dict = {}
        for feature in features:
            tools.update(load_toml(feature.mise_file).get("tools", {}))
            if feature.variant_mise_file:
                tools.update(load_toml(feature.variant_mise_file).get("tools", {}))
        if not tools:
            return
        print("[mise config]")
        _write_mise_toml(tools, MISE_CONFIG)
        print(f"  written {MISE_CONFIG}")
        print()

    def _capture_mise_versions(self, features: list[Feature]) -> None:
        live_tools = load_toml(MISE_CONFIG).get("tools", {})
        for feature in features:
            files = [feature.mise_file]
            if feature.variant_mise_file:
                files.append(feature.variant_mise_file)
            for mise_file in files:
                if not mise_file.exists():
                    continue
                feature_tools = load_toml(mise_file).get("tools", {})
                updated = {k: live_tools.get(k, v) for k, v in feature_tools.items()}
                if updated != feature_tools:
                    _write_mise_toml(updated, mise_file)
                    print(f"  updated {mise_file.relative_to(KAIZEN_DIR)}")


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
    try:
        overrides = read_toml(CONFIG_FILE)
        config = merge_config(read_toml(DEFAULTS_FILE), overrides)
        getattr(Kaizen(config), cmd)()
    except (OSError, TypeError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f"error: {error}")
        sys.exit(1)
