#!/usr/bin/env python3
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import TextIO, cast

import tomllib

KAIZEN_DIR = Path(__file__).parent
FEATURES_DIR = KAIZEN_DIR / "features"
DOTFILES_DIR = KAIZEN_DIR / "dotfiles"
CONFIG_FILE = Path.home() / ".config" / "kaizen" / "config.toml"
CONFIG_EXAMPLE_FILE = KAIZEN_DIR / "config.example.toml"
DEFAULTS_FILE = DOTFILES_DIR / ".chezmoidata.toml"
USER_DATA_FILE = DOTFILES_DIR / ".chezmoidata" / "99-user.toml"
MISE_CONFIG = Path.home() / ".config" / "mise.toml"

_CAPTURE_PATHS = [
    Path.home() / ".pi" / "agent" / "settings.json",
    Path.home() / ".pi" / "agent" / "mcp.json",
]
_VARIANT_FILES = ("packages.toml", "mise.toml", "post_install.py")
_FEATURE_ALIASES = {"battery-thresholds": "battery"}
_IGNORED_FEATURES = {"mise", "nix-system"}
_DOCUMENTATION_URL = "https://github.com/artawower/kaizen#readme"
_HOMEBREW_INSTALL_URL = (
    "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
)
_HOMEBREW_PATHS = (Path("/opt/homebrew/bin/brew"), Path("/usr/local/bin/brew"))
_ANSI_BOLD = "\033[1m"
_ANSI_CYAN = "\033[36m"
_ANSI_GREEN = "\033[32m"
_ANSI_YELLOW = "\033[33m"
_ANSI_RED = "\033[31m"
_ANSI_UNDERLINE = "\033[4m"
_ANSI_RESET = "\033[0m"


def _supports_color(stream: TextIO) -> bool:
    return (
        stream.isatty()
        and "NO_COLOR" not in os.environ
        and os.environ.get("TERM", "").lower() != "dumb"
    )


def _paint(text: object, *styles: str, stream: TextIO | None = None) -> str:
    output = stream if stream is not None else sys.stdout
    value = str(text)
    if not styles or not _supports_color(output):
        return value
    return f"{''.join(styles)}{value}{_ANSI_RESET}"


def _print_field(label: str, value: object, *styles: str) -> None:
    key = _paint(f"{label:<13}:", _ANSI_CYAN)
    print(f"{key} {_paint(value, *styles)}")


def _print_warning(message: str) -> None:
    print(_paint(message, _ANSI_YELLOW, stream=sys.stderr), file=sys.stderr)


def _print_error(message: str) -> None:
    print(
        _paint(f"error: {message}", _ANSI_RED, stream=sys.stderr),
        file=sys.stderr,
    )


class InstallMode(Enum):
    DEVELOPMENT = "development"
    MANAGED = "managed"


class CheckoutIssue(Enum):
    NOT_GIT = "is not a Git checkout"
    DIRTY = "has local changes"
    DETACHED = "has a detached HEAD"


class KaizenError(Exception):
    pass


class InstallModeError(KaizenError):
    def __init__(self, mode: str) -> None:
        self.mode = mode
        super().__init__(f"unknown installation mode: {mode}")


class CommandModeError(KaizenError):
    def __init__(
        self,
        command: str,
        current_mode: InstallMode,
        required_mode: InstallMode,
    ) -> None:
        self.command = command
        self.current_mode = current_mode
        self.required_mode = required_mode
        super().__init__(
            f"{command} requires {required_mode.value} mode "
            f"(current: {current_mode.value})"
        )


class ExecutableNotFoundError(KaizenError):
    def __init__(self, executable: str) -> None:
        self.executable = executable
        super().__init__(f"executable not found: {executable}")


class CheckoutError(KaizenError):
    def __init__(self, path: Path, issue: CheckoutIssue) -> None:
        self.path = path
        self.issue = issue
        super().__init__(f"self-update refused: {path} {issue.value}")


class ConfigNotFoundError(KaizenError):
    def __init__(self, path: Path, example: Path) -> None:
        self.path = path
        self.example = example
        super().__init__(f"config not found: {path}; copy {example} there")


class DependencyNotFoundError(KaizenError):
    def __init__(self, dependency: str, required_by: str, install_hint: str) -> None:
        self.dependency = dependency
        self.required_by = required_by
        self.install_hint = install_hint
        super().__init__(
            f"{dependency} is required by {required_by}; install it from {install_hint}"
        )


class DependencyInstallError(KaizenError):
    def __init__(self, dependency: str, exit_code: int | None = None) -> None:
        self.dependency = dependency
        self.exit_code = exit_code
        detail = f" with exit code {exit_code}" if exit_code is not None else ""
        super().__init__(f"failed to install {dependency}{detail}")


def _find_homebrew() -> str | None:
    if executable := shutil.which("brew"):
        return executable
    for path in _HOMEBREW_PATHS:
        if executable := shutil.which(str(path)):
            return executable
    return None


def _activate_homebrew(executable: str) -> str:
    bin_directory = str(Path(executable).parent)
    current_path = os.environ.get("PATH", "")
    entries = current_path.split(os.pathsep) if current_path else []
    if bin_directory not in entries:
        os.environ["PATH"] = os.pathsep.join([bin_directory, *entries])
    return executable


def _approve_install(dependency: str, required_by: str, install_source: str) -> bool:
    if not sys.stdin.isatty():
        return False
    try:
        answer = input(
            f"{dependency} is required by {required_by}. "
            f"Install it now from {install_source}? [y/N] "
        )
    except EOFError:
        return False
    return answer.strip().lower() in {"y", "yes"}


def _install_homebrew() -> str:
    if not shutil.which("curl"):
        raise ExecutableNotFoundError("curl")
    try:
        download = subprocess.run(
            ["curl", "-fsSL", _HOMEBREW_INSTALL_URL],
            check=True,
            capture_output=True,
            text=True,
        )
        result = subprocess.run(
            ["/bin/bash"],
            input=download.stdout,
            text=True,
            env={**os.environ, "NONINTERACTIVE": "1"},
        )
    except subprocess.CalledProcessError as error:
        raise DependencyInstallError("Homebrew", error.returncode) from error
    if result.returncode != 0:
        raise DependencyInstallError("Homebrew", result.returncode)
    if executable := _find_homebrew():
        return executable
    raise DependencyInstallError("Homebrew")


class PackageManager(ABC):
    @abstractmethod
    def install(self, packages: dict[str, object]) -> None:
        pass

    @abstractmethod
    def update(self) -> None:
        pass

    def _run(self, cmd: list[str], env: dict[str, str] | None = None) -> None:
        if not shutil.which(cmd[0]):
            raise ExecutableNotFoundError(cmd[0])
        print(f"  $ {' '.join(cmd)}")
        result = subprocess.run(cmd, env=env or os.environ)
        if result.returncode != 0:
            _print_warning(
                f"  warning: command failed (exit {result.returncode}), continuing"
            )


class Brew(PackageManager):
    def install(self, packages: dict[str, object]) -> None:
        section = _table(packages.get("macos"))
        taps = _string_list(section.get("taps"))
        formulae = _string_list(section.get("brew"))
        casks = _string_list(section.get("cask"))
        if not taps and not formulae and not casks:
            return
        brew = self._require("sync")
        for tap in taps:
            self._run([brew, "tap", tap])
        brew_args = _table(section.get("brew_args"))
        for package in formulae:
            self._run(
                [
                    brew,
                    "install",
                    "--yes",
                    package,
                    *_string_list(brew_args.get(package)),
                ]
            )
        if casks:
            self._run([brew, "install", "--yes", "--cask", *casks])

    def update(self) -> None:
        brew = self._require("update")
        self._run([brew, "update"])
        self._run([brew, "upgrade", "--yes"])

    @staticmethod
    def _require(required_by: str) -> str:
        if executable := _find_homebrew():
            return _activate_homebrew(executable)
        if _approve_install("Homebrew", required_by, _HOMEBREW_INSTALL_URL):
            return _activate_homebrew(_install_homebrew())
        raise DependencyNotFoundError("Homebrew", required_by, "https://brew.sh")


class Dnf(PackageManager):
    def install(self, packages: dict[str, object]) -> None:
        section = _table(packages.get("linux"))
        for pkg in _string_list(section.get("dnf")):
            self._run(["sudo", "dnf", "install", "-y", pkg])
        for app in _string_list(section.get("flatpak")):
            self._run(["sudo", "flatpak", "install", "--system", "-y", "flathub", app])

    def update(self) -> None:
        self._run(["sudo", "dnf", "upgrade", "-y"])


class Apt(PackageManager):
    def install(self, packages: dict[str, object]) -> None:
        section = _table(packages.get("linux"))
        for pkg in _string_list(section.get("apt")):
            self._run(["sudo", "apt", "install", "-y", pkg])
        for app in _string_list(section.get("flatpak")):
            self._run(["sudo", "flatpak", "install", "--system", "-y", "flathub", app])

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


def load_toml(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as error:
        _print_warning(f"  warning: {path}: {error}")
        return {}


def read_toml(path: Path) -> dict[str, object]:
    try:
        with open(path, "rb") as file:
            return tomllib.load(file)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"{path}: {error}") from error


def merge_config(
    defaults: dict[str, object], overrides: dict[str, object]
) -> dict[str, object]:
    merged = defaults.copy()
    for key, value in overrides.items():
        current = merged.get(key)
        if isinstance(value, dict) and isinstance(current, dict):
            merged[key] = merge_config(
                cast(dict[str, object], current), cast(dict[str, object], value)
            )
        else:
            merged[key] = value
    return merged


def _table(value: object) -> dict[str, object]:
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def _string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def _string_map(value: object) -> dict[str, str]:
    table = _table(value)
    return {key: item for key, item in table.items() if isinstance(item, str)}


def _mise_key(name: str) -> str:
    return f'"{name}"' if any(c in name for c in (":", "@", "/")) else name


def _toml_key(name: str) -> str:
    return (
        name
        if re.fullmatch(r"[A-Za-z0-9_-]+", name)
        else json.dumps(name, ensure_ascii=False)
    )


def _toml_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return f"[{', '.join(_toml_value(item) for item in value)}]"
    raise TypeError(f"unsupported TOML value: {type(value).__name__}")


def _append_toml_table(
    lines: list[str], path: tuple[str, ...], table: dict[str, object]
) -> None:
    if path:
        lines.append(f"[{'.'.join(_toml_key(part) for part in path)}]")
    scalar_items = []
    table_items = []
    for key, value in table.items():
        if not isinstance(key, str):
            raise TypeError("TOML keys must be strings")
        if isinstance(value, dict):
            table_items.append((key, value))
            continue
        scalar_items.append((key, value))
    for key, value in scalar_items:
        lines.append(f"{_toml_key(key)} = {_toml_value(value)}")
    for key, value in table_items:
        if lines and lines[-1] != "":
            lines.append("")
        _append_toml_table(lines, (*path, key), value)


def write_toml(data: dict[str, object], dest: Path) -> None:
    lines: list[str] = []
    _append_toml_table(lines, (), data)
    _ = dest.write_text("\n".join(lines) + "\n")


def _write_mise_toml(tools: dict[str, str], dest: Path) -> None:
    lines = ["[tools]"]
    for name, version in tools.items():
        if not isinstance(version, str):
            raise TypeError(f"mise version for {name} must be a string")
        lines.append(f'{_mise_key(name)} = "{version}"')
    _ = dest.write_text("\n".join(lines) + "\n")


def normalize_config(
    raw: dict[str, object],
) -> tuple[dict[str, object], list[str], bool]:
    legacy_schema = False
    renamed_features: set[str] = set()
    ignored_features: set[str] = set()
    normalized = {key: value for key, value in raw.items() if key != "settings"}

    if "settings" in raw:
        settings = raw["settings"]
        if not isinstance(settings, dict):
            raise TypeError("settings must be a table")
        normalized = merge_config(settings, normalized)
        legacy_schema = True

    configured = raw.get("features")
    if configured is not None:
        if not isinstance(configured, dict):
            raise TypeError("features must be a table")
        normalized_features: dict[str, bool] = {}
        for name, value in _table(configured).items():
            target = _FEATURE_ALIASES.get(name, name)
            if target != name:
                renamed_features.add(f"{name} -> {target}")
                legacy_schema = True
            if isinstance(value, bool):
                enabled = value
                feature_settings = {}
            elif isinstance(value, dict):
                feature_table = _table(value)
                enabled = feature_table.get("enabled", True)
                if not isinstance(enabled, bool):
                    raise TypeError(f"feature {name} enabled must be true or false")
                feature_settings = {
                    k: v for k, v in feature_table.items() if k != "enabled"
                }
                legacy_schema = True
            else:
                raise TypeError(f"feature {name} must be true or false")
            if target in _IGNORED_FEATURES:
                if enabled:
                    ignored_features.add(name)
                legacy_schema = True
                continue
            if target not in normalized_features or name == target:
                normalized_features[target] = enabled
            if feature_settings:
                existing = normalized.get(target, {})
                if not isinstance(existing, dict):
                    raise TypeError(f"settings for {target} must be a table")
                normalized[target] = merge_config(
                    feature_settings, cast(dict[str, object], existing)
                )
        normalized["features"] = normalized_features

    warnings = []
    if legacy_schema:
        warnings.append(f"warning: normalized legacy config schema in {CONFIG_FILE}")
    if renamed_features:
        warnings.append(
            f"warning: renamed legacy features: {', '.join(sorted(renamed_features))}"
        )
    if ignored_features:
        warnings.append(
            f"warning: ignored obsolete features: {', '.join(sorted(ignored_features))}"
        )
    return normalized, warnings, not legacy_schema


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


def parse_features(config: dict[str, object]) -> list[Feature]:
    configured = config.get("features", {})
    if not isinstance(configured, dict):
        raise TypeError("features must be a table")
    feature_table = _table(configured)
    available = {path.name for path in FEATURES_DIR.iterdir() if path.is_dir()}
    unknown = sorted(set(feature_table) - available)
    if unknown:
        raise ValueError(f"unknown features: {', '.join(unknown)}")
    result = []
    for name, enabled in feature_table.items():
        if not isinstance(enabled, bool):
            raise TypeError(f"feature {name} must be true or false")
        if not enabled:
            continue
        settings = config.get(name, {})
        if not isinstance(settings, dict):
            raise TypeError(f"settings for {name} must be a table")
        variant = _table(settings).get("variant")
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


def _install_mode() -> InstallMode:
    mode = os.environ.get("KAIZEN_INSTALL_MODE", InstallMode.DEVELOPMENT.value)
    try:
        return InstallMode(mode)
    except ValueError as error:
        raise InstallModeError(mode) from error


def _require_install_mode(command: str, required_mode: InstallMode) -> None:
    current_mode = _install_mode()
    if current_mode != required_mode:
        raise CommandModeError(command, current_mode, required_mode)


def _git_output(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(KAIZEN_DIR), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _self_update_branch() -> str:
    _require_install_mode("self-update", InstallMode.MANAGED)
    if not shutil.which("git"):
        raise ExecutableNotFoundError("git")
    if not (KAIZEN_DIR / ".git").exists():
        raise CheckoutError(KAIZEN_DIR, CheckoutIssue.NOT_GIT)
    if _git_output("status", "--porcelain"):
        raise CheckoutError(KAIZEN_DIR, CheckoutIssue.DIRTY)
    branch = _git_output("branch", "--show-current")
    if not branch:
        raise CheckoutError(KAIZEN_DIR, CheckoutIssue.DETACHED)
    return branch


def self_update() -> None:
    branch = _self_update_branch()
    before = _git_output("rev-parse", "--short", "HEAD")
    _ = subprocess.run(
        ["git", "-C", str(KAIZEN_DIR), "pull", "--ff-only", "origin", branch],
        check=True,
    )
    after = _git_output("rev-parse", "--short", "HEAD")
    if before == after:
        print(f"kaizen is already up to date ({after})")
        return
    print(f"updated kaizen: {before} -> {after}")
    print("run kaizen sync to apply the updated configuration")


class Kaizen:
    def __init__(
        self,
        config: dict[str, object],
        user_data: dict[str, object],
        link_user_config: bool,
    ) -> None:
        self._config = config
        self._user_data = user_data
        self._link_user_config = link_user_config
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
            _ = subprocess.run(["mise", "install", "--jobs=1"], check=True)
            print()
        for feature in features:
            self._run_post_install(feature, "sync")
        print("[dotfiles]")
        _ = subprocess.run(
            ["chezmoi", "apply", "--source", str(DOTFILES_DIR)], check=True
        )

    def update(self) -> None:
        features = parse_features(self._config)
        self._adapter.update()
        if shutil.which("mise"):
            _ = subprocess.run(["mise", "upgrade"], check=True)
        for feature in features:
            self._run_post_install(feature, "update")

    def bump(self) -> None:
        _require_install_mode("bump", InstallMode.DEVELOPMENT)
        _ = subprocess.run(["mise", "upgrade", "--bump", "--interactive"], check=False)
        self._capture_mise_versions(parse_features(self._config))
        self.capture()

    def capture(self) -> None:
        _require_install_mode("capture", InstallMode.DEVELOPMENT)
        for path in _CAPTURE_PATHS:
            if path.exists():
                _ = subprocess.run(
                    ["chezmoi", "re-add", "--source", str(DOTFILES_DIR), str(path)],
                    check=False,
                )
                print(f"  captured {path}")

    def status(self) -> None:
        features = parse_features(self._config)
        mode = _install_mode()
        mise_exists = MISE_CONFIG.exists()
        chezmoi = shutil.which("chezmoi")
        mise = shutil.which("mise")
        _print_field("OS", self._os)
        _print_field(
            "mode",
            mode.value,
            _ANSI_GREEN if mode is InstallMode.MANAGED else _ANSI_YELLOW,
        )
        _print_field("source", KAIZEN_DIR)
        _print_field("config", CONFIG_FILE)
        _print_field("features", ", ".join(feature.label for feature in features))
        _print_field(
            "mise config",
            f"{MISE_CONFIG} {'(exists)' if mise_exists else '(not generated yet)'}",
            _ANSI_GREEN if mise_exists else _ANSI_YELLOW,
        )
        _print_field(
            "chezmoi", chezmoi or "not found", _ANSI_GREEN if chezmoi else _ANSI_RED
        )
        _print_field("mise", mise or "not found", _ANSI_GREEN if mise else _ANSI_RED)

    def _write_user_data(self) -> None:
        USER_DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
        if USER_DATA_FILE.is_symlink() or USER_DATA_FILE.exists():
            USER_DATA_FILE.unlink()
        if self._link_user_config:
            USER_DATA_FILE.symlink_to(CONFIG_FILE)
            return
        write_toml(self._user_data, USER_DATA_FILE)

    def _install_packages(self, feature: Feature) -> None:
        print(f"[{feature.label}]")
        self._adapter.install(load_toml(feature.packages_file))
        if feature.variant_packages_file:
            self._adapter.install(load_toml(feature.variant_packages_file))
        print()

    def _run_post_install(self, feature: Feature, action: str) -> None:
        scripts = [feature.post_install]
        if feature.variant_post_install:
            scripts.append(feature.variant_post_install)
        existing = [script for script in scripts if script.exists()]
        if not existing:
            return
        print(f"[{feature.label} post-install]")
        for script in existing:
            _ = subprocess.run(
                [sys.executable, str(script), self._os, action], check=True
            )
        print()

    def _generate_mise_config(self, features: list[Feature]) -> None:
        tools: dict[str, str] = {}
        for feature in features:
            tools.update(_string_map(load_toml(feature.mise_file).get("tools")))
            if feature.variant_mise_file:
                tools.update(
                    _string_map(load_toml(feature.variant_mise_file).get("tools"))
                )
        if not tools:
            return
        print("[mise config]")
        _write_mise_toml(tools, MISE_CONFIG)
        print(f"  written {MISE_CONFIG}")
        print()

    def _capture_mise_versions(self, features: list[Feature]) -> None:
        live_tools = _string_map(load_toml(MISE_CONFIG).get("tools"))
        for feature in features:
            files = [feature.mise_file]
            if feature.variant_mise_file:
                files.append(feature.variant_mise_file)
            for mise_file in files:
                if not mise_file.exists():
                    continue
                feature_tools = _string_map(load_toml(mise_file).get("tools"))
                updated = {k: live_tools.get(k, v) for k, v in feature_tools.items()}
                if updated != feature_tools:
                    _write_mise_toml(updated, mise_file)
                    print(f"  updated {mise_file.relative_to(KAIZEN_DIR)}")


_COMMANDS = {
    "sync": "Install enabled packages, mise tools, and dotfiles",
    "update": "Upgrade native packages, mise tools, and feature integrations",
    "self-update": "Update a managed Kaizen installation",
    "status": "Show the active platform, features, and tools",
    "bump": "Developer: upgrade and capture mise versions",
    "capture": "Developer: capture mutable dotfiles",
    "docs": "Show documentation and configuration paths",
    "help": "Show this help",
}


def _print_help() -> None:
    print(f"{_paint('Usage:', _ANSI_BOLD)} kaizen <command>\n")
    print(_paint("Commands:", _ANSI_BOLD))
    for name, description in _COMMANDS.items():
        command = _paint(f"{name:<12}", _ANSI_CYAN)
        print(f"  {command} {description}")
    print(f"\n{_paint('Documentation:', _ANSI_BOLD)}")
    print(f"  {_paint(_DOCUMENTATION_URL, _ANSI_CYAN, _ANSI_UNDERLINE)}")
    print(f"\n{_paint('Configuration:', _ANSI_BOLD)}")
    print(f"  {CONFIG_FILE}")


def _print_docs() -> None:
    _print_field("Documentation", _DOCUMENTATION_URL, _ANSI_CYAN, _ANSI_UNDERLINE)
    _print_field("Configuration", CONFIG_FILE)
    _print_field("Installed source", KAIZEN_DIR)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd in {"help", "-h", "--help"}:
        _print_help()
        sys.exit()
    if cmd == "docs":
        _print_docs()
        sys.exit()
    if cmd not in _COMMANDS:
        _print_error(f"unknown command: {cmd}. available: {', '.join(_COMMANDS)}")
        sys.exit(1)
    try:
        if cmd == "self-update":
            self_update()
        else:
            if not CONFIG_FILE.exists():
                raise ConfigNotFoundError(CONFIG_FILE, CONFIG_EXAMPLE_FILE)
            overrides = read_toml(CONFIG_FILE)
            normalized_overrides, warnings, link_user_config = normalize_config(
                overrides
            )
            config = merge_config(read_toml(DEFAULTS_FILE), normalized_overrides)
            for warning in warnings:
                _print_warning(warning)
            getattr(Kaizen(config, normalized_overrides, link_user_config), cmd)()
    except subprocess.CalledProcessError as error:
        command = " ".join(str(part) for part in error.cmd)
        _print_error(f"{command} failed with exit code {error.returncode}")
        sys.exit(error.returncode)
    except (
        KaizenError,
        OSError,
        TypeError,
        ValueError,
        tomllib.TOMLDecodeError,
    ) as error:
        _print_error(str(error))
        sys.exit(1)
