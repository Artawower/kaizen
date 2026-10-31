#!/usr/bin/env python3
import argparse
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import TextIO, cast

KAIZEN_DIR = Path(__file__).parent
FEATURES_DIR = KAIZEN_DIR / "features"
DOTFILES_DIR = KAIZEN_DIR / "dotfiles"
CONFIG_FILE = Path.home() / ".config" / "kaizen" / "config.toml"
USER_DEPENDENCIES_FILE = CONFIG_FILE.with_name("dependencies.toml")
CONFIG_EXAMPLE_FILE = KAIZEN_DIR / "config.example.toml"
USER_DATA_FILE = DOTFILES_DIR / ".chezmoidata" / "99-user.toml"
MISE_CONFIG = Path.home() / ".config" / "mise.toml"
BOOTSTRAP_CONFIG = CONFIG_FILE.with_name("bootstrap.toml")

_CAPTURE_PATHS = [
    Path.home() / ".pi" / "agent" / "settings.json",
    Path.home() / ".pi" / "agent" / "mcp.json",
    Path.home() / ".claude" / "settings.json",
]
_USER_MACOS_DEPENDENCY_LISTS = ("taps", "brew", "cask")
_USER_LINUX_DEPENDENCY_LISTS = ("dnf", "apt", "flatpak")
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


def _require_homebrew(required_by: str) -> str:
    if executable := _find_homebrew():
        return _activate_homebrew(executable)
    if _approve_install("Homebrew", required_by, _HOMEBREW_INSTALL_URL):
        return _activate_homebrew(_install_homebrew())
    raise DependencyNotFoundError("Homebrew", required_by, "https://brew.sh")


def _run_mise(config: Path, arguments: list[str]) -> None:
    with TemporaryDirectory(prefix="kaizen-mise-") as directory:
        environment = {
            **os.environ,
            "MISE_GLOBAL_CONFIG_FILE": str(config),
            "MISE_GLOBAL_CONFIG_ROOT": str(KAIZEN_DIR),
            "MISE_SYSTEM_CONFIG_FILE": str(Path(directory) / "system.toml"),
            "MISE_CONFIG_DIR": directory,
            "MISE_SYSTEM_CONFIG_DIR": directory,
            "MISE_OVERRIDE_CONFIG_FILENAMES": "kaizen-no-project.toml",
            "MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES": "kaizen-no-tool-versions",
            "MISE_CEILING_PATHS": os.pathsep.join(map(str, (config.parent, KAIZEN_DIR, Path.home()))),
            "MISE_ENV": "",
            "MISE_AUTO_ENV": "false",
        }
        subprocess.run(
            ["mise", "--jobs=1", *arguments], cwd=config.parent,
            env=environment, check=True,
        )


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


def load_toml(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    return read_toml(path)


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


def _validate_keys(table: dict[str, object], allowed: set[str], label: str) -> None:
    unknown = sorted(set(table) - allowed)
    if not unknown:
        return
    raise ValueError(f"{label}: unknown keys: {', '.join(unknown)}")


def _dependency_table(
    dependencies: dict[str, object], key: str, path: Path
) -> dict[str, object]:
    value = dependencies.get(key)
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise TypeError(f"{path}: {key} must be a table")
    return cast(dict[str, object], value)


def _validate_string_list(table: dict[str, object], key: str, label: str) -> None:
    value = table.get(key)
    if value is None:
        return
    if isinstance(value, list) and all(
        isinstance(item, str) and item for item in value
    ):
        return
    raise TypeError(f"{label}.{key} must be a list of non-empty strings")


def _validate_string_map(table: dict[str, object], label: str) -> None:
    invalid = sorted(
        key
        for key, value in table.items()
        if not key or not isinstance(value, str) or not value
    )
    if not invalid:
        return
    raise TypeError(f"{label} values must be non-empty strings: {', '.join(invalid)}")


def load_user_dependencies(
    path: Path | None = None,
) -> dict[str, object]:
    path = USER_DEPENDENCIES_FILE if path is None else path
    if not path.exists():
        return {}
    dependencies = read_toml(path)
    _validate_keys(dependencies, {"tools", "macos", "linux"}, str(path))
    tools = _dependency_table(dependencies, "tools", path)
    _validate_string_map(tools, f"{path}: tools")
    macos = _dependency_table(dependencies, "macos", path)
    _validate_keys(
        macos, {*_USER_MACOS_DEPENDENCY_LISTS, "brew_args"}, f"{path}: macos"
    )
    for key in _USER_MACOS_DEPENDENCY_LISTS:
        _validate_string_list(macos, key, f"{path}: macos")
    brew_args = _dependency_table(macos, "brew_args", path)
    for package in brew_args:
        _validate_string_list(brew_args, package, f"{path}: macos.brew_args")
    linux = _dependency_table(dependencies, "linux", path)
    _validate_keys(linux, set(_USER_LINUX_DEPENDENCY_LISTS), f"{path}: linux")
    for key in _USER_LINUX_DEPENDENCY_LISTS:
        _validate_string_list(linux, key, f"{path}: linux")
    return dependencies


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
    if isinstance(value, dict):
        items = (
            f"{_toml_key(key)} = {_toml_value(item)}"
            for key, item in value.items()
        )
        return f"{{{', '.join(items)}}}"
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
        lines.append(f"{_toml_key(name)} = {_toml_value(version)}")
    _ = dest.write_text("\n".join(lines) + "\n")


def _write_feature_catalog(data: dict[str, object], dest: Path) -> None:
    lines: list[str] = []
    for name, section in data.items():
        lines.append(f"[{_toml_key(name)}]")
        for key, value in _table(section).items():
            lines.append(f"{_toml_key(key)} = {_toml_value(value)}")
        lines.append("")
    _ = dest.write_text("\n".join(lines))


def normalize_config(
    raw: dict[str, object],
) -> tuple[dict[str, object], list[str]]:
    normalized = {key: value for key, value in raw.items() if key != "settings"}
    warnings = []
    if "settings" in raw:
        if not isinstance(raw["settings"], dict):
            raise TypeError("settings must be a table")
        normalized = merge_config(_table(raw["settings"]), normalized)
        warnings.append(f"warning: normalized legacy settings in {CONFIG_FILE}")
    if "features" in normalized:
        raise ValueError(
            "[features] is no longer supported; remove it from the user config. "
            "All non-archived features for this OS are active; "
            "set archive = true in unwanted feature sections."
        )
    for name in ("tiling", "helix"):
        if "variant" in _table(normalized.get(name)):
            raise ValueError(
                f"[{name}].variant is no longer supported; "
                "implementations are independent catalog entries"
            )
    return normalized, warnings


@dataclass
class Feature:
    manifest: Path
    name: str
    data: dict[str, object]

    @property
    def label(self) -> str:
        return f"{self.manifest.stem}/{self.name}"

    @property
    def packages(self) -> dict[str, object]:
        return {
            "packages": self.data.get("packages", []),
            "macos": {
                key: self.data[key]
                for key in (*_USER_MACOS_DEPENDENCY_LISTS, "brew_args")
                if key in self.data
            },
            "linux": {
                key: self.data[key]
                for key in _USER_LINUX_DEPENDENCY_LISTS
                if key in self.data
            },
        }

    @property
    def tools(self) -> dict[str, str]:
        return _string_map(self.data.get("tools"))

    @property
    def skills(self) -> list[str]:
        return _string_list(self.data.get("skills"))

    @property
    def post_install(self) -> Path | None:
        hook = self.data.get("post_install")
        return KAIZEN_DIR / hook if isinstance(hook, str) else None

    def active_on(self, os_name: str) -> bool:
        label = f"{self.manifest}: {self.name}"
        archived = self.data.get("archive", False)
        if not isinstance(archived, bool):
            raise TypeError(f"{label}: archive must be true or false")
        if archived:
            return False
        list_keys = (
            *_USER_MACOS_DEPENDENCY_LISTS, *_USER_LINUX_DEPENDENCY_LISTS,
            "platforms", "distributions", "dotfiles", "skills", "packages",
        )
        _validate_keys(
            self.data,
            {*list_keys, "archive", "description", "tools", "brew_args", "package_names", "post_install", "bootstrap"},
            label,
        )
        for key in list_keys:
            _validate_string_list(self.data, key, label)
        for skill in self.skills:
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[\w.-]+@[\w.-]+", skill, re.ASCII):
                raise ValueError(f"{label}: skill must use owner/repo@skill format: {skill}")
        tools = _dependency_table(self.data, "tools", self.manifest)
        _validate_string_map(tools, f"{label}: tools")
        brew_args = _dependency_table(self.data, "brew_args", self.manifest)
        for package in brew_args:
            _validate_string_list(brew_args, package, f"{label}: brew_args")
        package_names = _dependency_table(self.data, "package_names", self.manifest)
        for name in package_names:
            if not name:
                raise ValueError(f"{label}: package_names keys must be non-empty")
            overrides = _dependency_table(package_names, name, self.manifest)
            _validate_keys(overrides, {"brew", "dnf", "apt"}, f"{label}: package_names.{name}")
            _validate_string_map(overrides, f"{label}: package_names.{name}")
        _dependency_table(self.data, "bootstrap", self.manifest)
        for source in _string_list(self.data.get("dotfiles")):
            path = Path(source)
            if path.is_absolute() or ".." in path.parts or len(path.parts) < 2 or path.parts[0] != "dotfiles" or "\n" in source:
                raise ValueError(f"{label}: dotfiles paths must be inside dotfiles/")
        hook = self.data.get("post_install")
        if hook is not None:
            if not isinstance(hook, str) or not hook:
                raise TypeError(f"{label}: post_install must be a non-empty path")
            if Path(hook).is_absolute() or ".." in Path(hook).parts:
                raise ValueError(f"{label}: post_install must be repository-relative")
        platforms = self.data.get("platforms", ["macos", "linux"])
        if not platforms or set(cast(list[str], platforms)) - {"macos", "linux"}:
            raise ValueError(f"{label}: platforms must contain macos and/or linux")
        platform_key = "macos" if os_name == "macos" else "linux"
        if platform_key not in cast(list[str], platforms):
            return False
        distributions = self.data.get("distributions")
        return (
            platform_key != "linux" or distributions is None
            or os_name in cast(list[str], distributions)
        )


def discover_features(
    os_name: str, selected: list[str] | None = None,
) -> list[Feature]:
    result = []
    names: set[str] = set()
    for manifest in sorted(FEATURES_DIR.glob("*.toml")):
        for name, data in sorted(read_toml(manifest).items()):
            if not isinstance(data, dict):
                raise TypeError(f"{manifest}: {name} must be a feature table")
            if name in names:
                raise ValueError(f"duplicate feature name: {name}")
            names.add(name)
            feature = Feature(manifest, name, data)
            active = feature.active_on(os_name)
            if active and (selected is None or name in selected):
                hook = feature.post_install
                if hook is not None and not hook.is_file():
                    raise FileNotFoundError(f"{feature.label}: hook not found: {hook}")
                result.append(feature)
    if selected is not None:
        unknown = set(selected) - names
        if unknown:
            raise ValueError(f"unknown features: {', '.join(sorted(unknown))}")
        inactive = set(selected) - {feature.name for feature in result}
        if inactive:
            raise ValueError(
                f"archived or unsupported features for {os_name}: {', '.join(sorted(inactive))}"
            )
    return result


def _resolve_packages(
    features: list[Feature], user_dependencies: dict[str, object]
) -> dict[str, object]:
    names: dict[str, dict[str, str]] = {}
    origins: dict[tuple[str, str], str] = {}
    aliases: dict[str, tuple[str, str]] = {}
    for feature in features:
        for name, value in _table(feature.data.get("package_names")).items():
            overrides = _string_map(value)
            for alias in (name, *overrides.values()):
                previous, source = aliases.get(alias, (name, feature.label))
                if previous != name:
                    raise ValueError(
                        f"ambiguous package alias {alias!r}: "
                        f"{previous!r} in {source} and {name!r} in {feature.label}"
                    )
                aliases.setdefault(alias, (name, feature.label))
            for manager, package in overrides.items():
                existing = names.setdefault(name, {}).get(manager)
                if existing is not None and existing != package:
                    raise ValueError(
                        f"conflicting package_names for {name!r} ({manager}): "
                        f"{existing!r} in {origins[name, manager]} and "
                        f"{package!r} in {feature.label}"
                    )
                names[name][manager] = package
                origins[name, manager] = feature.label

    result: dict[str, object] = {"macos": {}, "linux": {}}
    brew_args: dict[str, tuple[list[str], str]] = {}
    declarations = [
        *((feature.label, feature.packages) for feature in features),
        ("user dependencies", user_dependencies),
    ]
    for label, dependencies in declarations:
        common = _string_list(dependencies.get("packages"))
        for platform_key, managers in (
            ("macos", _USER_MACOS_DEPENDENCY_LISTS),
            ("linux", _USER_LINUX_DEPENDENCY_LISTS),
        ):
            section = _table(dependencies.get(platform_key))
            target = _table(result[platform_key])
            for manager in managers:
                requested = _string_list(section.get(manager))
                if manager in {"brew", "dnf", "apt"}:
                    shared = []
                    for name in common:
                        canonical = aliases.get(name, (name, ""))[0]
                        shared.append(names.get(canonical, {}).get(manager, canonical))
                    requested = [*shared, *requested]
                    for package in requested:
                        canonical = aliases.get(package, (package, ""))[0]
                        expected = names.get(canonical, {}).get(manager, canonical)
                        if package != expected:
                            raise ValueError(
                                f"{label}: {manager} package {package!r} must be "
                                f"{expected!r}; use packages for shared aliases"
                            )
                if manager == "brew":
                    for package in requested:
                        flags = _string_list(_table(section.get("brew_args")).get(package))
                        previous_flags, source = brew_args.get(package, (flags, label))
                        if previous_flags != flags:
                            raise ValueError(
                                f"conflicting brew_args for {package!r}: "
                                f"{previous_flags!r} in {source} and {flags!r} in {label}"
                            )
                        brew_args[package] = (flags, label)
                        if flags:
                            _table(target.setdefault("brew_args", {}))[package] = flags
                if requested:
                    target[manager] = list(dict.fromkeys([
                        *_string_list(target.get(manager)), *requested,
                    ]))
    return result


def _merge_bootstrap(
    target: dict[str, object], source: dict[str, object], label: str,
) -> None:
    for key, value in source.items():
        if key not in target:
            target[key] = merge_config({}, value) if isinstance(value, dict) else value
        elif isinstance(target[key], dict) and isinstance(value, dict):
            _merge_bootstrap(_table(target[key]), value, f"{label}.{key}")
        elif target[key] != value:
            raise ValueError(f"conflicting bootstrap declaration: {label}.{key}")


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
        self, user_data: dict[str, object], selected: list[str] | None = None,
        dry_run: bool = False,
    ) -> None:
        self._user_data = user_data
        self._os = detect_os()
        self._selected = selected
        self._dry_run = dry_run

    def _features(self) -> list[Feature]:
        return discover_features(self._os, self._selected)

    def install(self) -> None:
        self._execute("sync", dotfiles=False)

    def sync(self) -> None:
        self._execute("sync", dotfiles=True)

    def update(self) -> None:
        self._execute("update", dotfiles=False)

    def _selected_dotfiles(self, features: list[Feature]) -> list[str]:
        sources = list(dict.fromkeys(
            source for feature in features
            for source in _string_list(feature.data.get("dotfiles"))
        ))
        for source in sources:
            path = KAIZEN_DIR / source
            if not path.resolve().is_relative_to(DOTFILES_DIR.resolve()):
                raise ValueError(f"dotfile path escapes source directory: {source}")
            if not path.exists():
                raise FileNotFoundError(f"dotfile source not found: {source}")
        return [str(KAIZEN_DIR / source) for source in sources]

    @staticmethod
    def _integration_command(name: str, features: list[Feature]) -> list[str]:
        command = [sys.executable, str(KAIZEN_DIR / "kaizen.py"), name]
        for feature in features:
            command.extend(["--feature", feature.name])
        return command

    def _dotfiles_command(self, features: list[Feature]) -> list[str]:
        if self._selected is None:
            return ["chezmoi", "apply", "--source", str(DOTFILES_DIR)]
        if not self._selected_dotfiles(features):
            return []
        return self._integration_command("_dotfiles", features)

    def _apply_dotfiles(self) -> None:
        sources = self._selected_dotfiles(self._features())
        if not sources:
            return
        base = ["chezmoi", "--source", str(DOTFILES_DIR)]
        resolved = subprocess.run(
            [*base, "target-path", *sources], capture_output=True, text=True, check=True,
        )
        targets = resolved.stdout.splitlines()
        if not targets:
            return
        managed = subprocess.run(
            [*base, "managed", "--path-style", "absolute", "--nul-path-separator", *targets],
            capture_output=True, text=True, check=True,
        )
        entries = set(managed.stdout.split("\0"))
        paths = [target for target in targets if target in entries]
        if paths:
            subprocess.run(
                [*base, "apply", "--parent-dirs", "--", *paths],
                check=True,
            )

    def _bootstrap_config(
        self, features: list[Feature], dependencies: dict[str, object],
        action: str, *, dotfiles: bool,
    ) -> dict[str, object]:
        packages = _resolve_packages(features, dependencies)
        bootstrap: dict[str, object] = {}
        tools: dict[str, str] = {}
        for feature in features:
            declaration = _table(feature.data.get("bootstrap"))
            if {"packages", "hooks"} & declaration.keys():
                raise ValueError(f"{feature.label}: bootstrap packages and hooks are generated by Kaizen")
            _merge_bootstrap(bootstrap, declaration, feature.label)
            tools.update(feature.tools)
        tools.update(_string_map(dependencies.get("tools")))
        commands: list[str] = []
        if self._os == "macos":
            section = _table(packages["macos"])
            brew = _find_homebrew() or "brew"
            taps = _string_list(section.get("taps"))
            formulae = _string_list(section.get("brew"))
            casks = _string_list(section.get("cask"))
            commands.extend(shlex.join([brew, "tap", tap]) for tap in taps)
            if action == "update" and (formulae or casks):
                commands.append(shlex.join([brew, "update"]))
            for package in formulae:
                flags = _string_list(_table(section.get("brew_args")).get(package))
                commands.append(shlex.join([brew, "install", "--yes", package, *flags]))
                if action == "update":
                    commands.append(shlex.join([brew, "upgrade", "--yes", package, *flags]))
            if casks:
                commands.append(shlex.join([brew, "install", "--yes", "--cask", *casks]))
                if action == "update":
                    commands.append(shlex.join([brew, "upgrade", "--yes", "--cask", *casks]))
        else:
            section = _table(packages["linux"])
            manager = {"ubuntu": "apt", "debian": "apt", "fedora": "dnf", "rhel": "dnf", "fedora-asahi-remix": "dnf"}.get(self._os)
            if manager is None and any(section.get(key) for key in ("apt", "dnf")):
                raise ValueError(f"unsupported native package manager for {self._os}")
            native = {
                f"{manager}:{package}": "latest"
                for package in _string_list(section.get(manager or ""))
            }
            native.update({
                f"flatpak:{package}": "latest"
                for package in _string_list(section.get("flatpak"))
            })
            if native:
                bootstrap["packages"] = native
        if commands:
            bootstrap["hooks"] = {"pre-packages": commands}
        tasks: list[str] = []
        skills = list(dict.fromkeys(skill for feature in features for skill in feature.skills))
        if len({skill.rsplit("@", 1)[1] for skill in skills}) != len(skills):
            raise ValueError("skills inventory contains different sources for the same skill name")
        if skills:
            command = self._integration_command("_skills", features)
            if action == "update":
                command.append("--refresh")
            tasks.append(shlex.join(command))
        for feature in features:
            if feature.post_install is not None:
                tasks.append(shlex.join([
                    sys.executable, str(feature.post_install), self._os, action,
                ]))
        if dotfiles and (command := self._dotfiles_command(features)):
            tasks.append(shlex.join(command))
        config: dict[str, object] = {"tools": tools, "bootstrap": bootstrap}
        if tasks:
            config["tasks"] = {"bootstrap": {"run": tasks, "dir": str(KAIZEN_DIR), "raw": True}}
        return config

    def _execute(self, action: str, *, dotfiles: bool) -> None:
        features = self._features()
        dependencies = load_user_dependencies()
        config = self._bootstrap_config(features, dependencies, action, dotfiles=dotfiles)
        if not shutil.which("mise"):
            raise DependencyNotFoundError("mise", action, "https://mise.jdx.dev/")
        if dotfiles and self._dotfiles_command(features) and not shutil.which("chezmoi"):
            raise DependencyNotFoundError("chezmoi", "sync", "https://www.chezmoi.io/install/")
        capability = subprocess.run(
            ["mise", "--no-config", "bootstrap", "--help"], capture_output=True, text=True, check=False,
        )
        if capability.returncode != 0 or "--upgrade" not in capability.stdout:
            raise DependencyNotFoundError("mise bootstrap with --upgrade", action, "https://mise.jdx.dev/getting-started.html")
        arguments = ["bootstrap"]
        if action == "update":
            arguments.extend(["--update", "--upgrade"])
        if self._dry_run:
            with TemporaryDirectory(prefix="kaizen-plan-") as directory:
                path = Path(directory) / "bootstrap.toml"
                write_toml(config, path)
                _run_mise(path, [*arguments, "--dry-run"])
            return
        if self._os == "macos" and _table(config["bootstrap"]).get("hooks"):
            _require_homebrew(action)
            config = self._bootstrap_config(features, dependencies, action, dotfiles=dotfiles)
        managers = {key.split(":", 1)[0] for key in _table(_table(config["bootstrap"]).get("packages"))}
        for manager in sorted(managers):
            if not shutil.which(manager):
                raise ExecutableNotFoundError(manager)
        if any(key.startswith("flatpak:") for key in _table(_table(config["bootstrap"]).get("packages"))):
            remotes = subprocess.run(
                ["flatpak", "remotes", "--system", "--columns=name"],
                capture_output=True, text=True, check=True,
            )
            if "flathub" not in remotes.stdout.splitlines():
                raise ValueError("Flatpak requires a system-wide flathub remote; configure it before syncing")
        BOOTSTRAP_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        write_toml(config, BOOTSTRAP_CONFIG)
        self._generate_mise_config(features, dependencies)
        if dotfiles:
            self._write_user_data()
        _run_mise(BOOTSTRAP_CONFIG, arguments)

    def cleanup(self) -> None:
        steps: list[tuple[str, list[str]]] = []
        projects = Path.home() / "projects"

        if self._os == "macos" and shutil.which("mo"):
            steps.append(("mole", ["mo", "clean"]))
        if shutil.which("kondo") and projects.is_dir():
            steps.append(("kondo", ["kondo", str(projects)]))
        if shutil.which("go"):
            steps.append(("go", ["go", "clean", "-cache", "-modcache"]))
        if self._cargo_cache_available():
            steps.append(("cargo", ["cargo", "cache", "--autoclean"]))
        if shutil.which("uv"):
            steps.append(("uv", ["uv", "cache", "clean"]))
        if shutil.which("npm"):
            steps.append(("npm", ["npm", "cache", "clean", "--force"]))
        if shutil.which("pnpm"):
            steps.append(("pnpm", ["pnpm", "store", "prune"]))
        if shutil.which("bun"):
            steps.append(("bun", ["bun", "pm", "cache", "rm"]))

        for label, cmd in steps:
            print(f"[{label}]")
            _ = subprocess.run(cmd, check=False)

    @staticmethod
    def _cargo_cache_available() -> bool:
        if not shutil.which("cargo"):
            return False
        probe = subprocess.run(
            ["cargo", "cache", "--version"], capture_output=True, check=False
        )
        return probe.returncode == 0

    def bump(self) -> None:
        _require_install_mode("bump", InstallMode.DEVELOPMENT)
        features = self._features()
        user_dependencies = load_user_dependencies()
        user_tools = set(_string_map(user_dependencies.get("tools")))
        self._generate_mise_config(features, user_dependencies)
        _run_mise(MISE_CONFIG, ["upgrade", "--bump", "--interactive"])
        self._capture_mise_versions(features, user_tools)
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
        features = self._features()
        _ = load_user_dependencies()
        mode = _install_mode()
        dependencies_exist = USER_DEPENDENCIES_FILE.exists()
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
        _print_field(
            "dependencies",
            f"{USER_DEPENDENCIES_FILE} "
            f"{'(configured)' if dependencies_exist else '(not configured)'}",
            _ANSI_GREEN if dependencies_exist else _ANSI_YELLOW,
        )
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
        if USER_DATA_FILE.is_symlink():
            USER_DATA_FILE.unlink()
        write_toml(self._user_data, USER_DATA_FILE)

    def _install_skills(self, features: list[Feature], *, update: bool = False) -> None:
        packages = list(dict.fromkeys(skill for feature in features for skill in feature.skills))
        if not packages:
            return
        if len({package.rsplit("@", 1)[1] for package in packages}) != len(packages):
            raise ValueError("skills inventory contains different sources for the same skill name")
        skills = shutil.which("skills")
        command = [skills] if skills else []
        if not command and (mise := shutil.which("mise")):
            resolved = subprocess.run(
                [mise, "which", "skills"], check=False,
                cwd=Path.home(), capture_output=True, text=True,
            )
            if resolved.returncode == 0:
                command = [mise, "exec", "--", "skills"]
        if not command:
            _print_warning("skipping skill installation: skills CLI is not available")
            return
        print("[skills]")
        result = subprocess.run(
            [*command, "list", "-g", "--json"], cwd=Path.home(),
            check=True, capture_output=True, text=True,
        )
        try:
            records = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise ValueError("skills list returned invalid JSON") from error
        if not isinstance(records, list) or any(
            not isinstance(item, dict) or not isinstance(item.get("name"), str)
            or item.get("source") is not None and not isinstance(item["source"], str)
            for item in records
        ):
            raise ValueError("skills list must return a JSON array of skill records")
        installed = {(item["name"], item.get("source")) for item in records}
        for package in packages:
            source, name = package.rsplit("@", 1)
            if not update and (name, source) in installed:
                continue
            _ = subprocess.run(
                [*command, "add", package, "-g", "-y"], cwd=Path.home(), check=True,
            )
        print()

    def _generate_mise_config(
        self, features: list[Feature], user_dependencies: dict[str, object]
    ) -> None:
        tools: dict[str, str] = {}
        for feature in features:
            tools.update(feature.tools)
        tools.update(_string_map(user_dependencies.get("tools")))
        if not tools:
            MISE_CONFIG.unlink(missing_ok=True)
            return
        print("[mise config]")
        MISE_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        _write_mise_toml(tools, MISE_CONFIG)
        print(f"  written {MISE_CONFIG}")
        print()

    def _capture_mise_versions(
        self, features: list[Feature], user_tools: set[str]
    ) -> None:
        live_tools = _string_map(load_toml(MISE_CONFIG).get("tools"))
        for feature in features:
            feature_tools = feature.tools
            updated = {
                key: version if key in user_tools else live_tools.get(key, version)
                for key, version in feature_tools.items()
            }
            if updated != feature_tools:
                catalog = read_toml(feature.manifest)
                _table(catalog[feature.name])["tools"] = updated
                _write_feature_catalog(catalog, feature.manifest)
                feature.data["tools"] = updated
                print(f"  updated {feature.manifest.relative_to(KAIZEN_DIR)} [{feature.name}]")


_COMMANDS = {
    "install": "Install non-archived features for the current OS",
    "sync": "Install dependencies and apply dotfiles",
    "update": "Upgrade native packages, mise tools, and feature integrations",
    "self-update": "Update a managed Kaizen installation",
    "cleanup": "Clean system and toolchain caches",
    "status": "Show the active platform, features, and tools",
    "bump": "Developer: upgrade and capture mise versions",
    "capture": "Developer: capture mutable dotfiles",
    "docs": "Show documentation and configuration paths",
    "help": "Show this help",
}


def _print_help() -> None:
    print(f"{_paint('Usage:', _ANSI_BOLD)} kaizen <command> [--feature NAME]... [--dry-run]\n")
    print(_paint("Commands:", _ANSI_BOLD))
    for name, description in _COMMANDS.items():
        command = _paint(f"{name:<12}", _ANSI_CYAN)
        print(f"  {command} {description}")
    print("\nRepeat --feature to select recipes; omission selects all active recipes.")
    print("--dry-run previews install, sync, or update; hooks and tasks are not executed.")
    print(f"\n{_paint('Documentation:', _ANSI_BOLD)}")
    print(f"  {_paint(_DOCUMENTATION_URL, _ANSI_CYAN, _ANSI_UNDERLINE)}")
    print(f"\n{_paint('Configuration:', _ANSI_BOLD)}")
    print(f"  settings:     {CONFIG_FILE}")
    print(f"  dependencies: {USER_DEPENDENCIES_FILE}")


def _print_docs() -> None:
    _print_field("Documentation", _DOCUMENTATION_URL, _ANSI_CYAN, _ANSI_UNDERLINE)
    _print_field("Configuration", CONFIG_FILE)
    _print_field("Dependencies", USER_DEPENDENCIES_FILE)
    _print_field("Mise plan", BOOTSTRAP_CONFIG)
    _print_field("Installed source", KAIZEN_DIR)


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", nargs="?", default="help")
    parser.add_argument("--feature", action="append", dest="features")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--refresh", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("-h", "--help", action="store_true")
    options = parser.parse_args()
    cmd = "help" if options.help else options.command
    if options.features and cmd not in {"install", "sync", "update", "status", "bump", "_skills", "_dotfiles"}:
        parser.error(f"--feature is not supported by {cmd}")
    if options.dry_run and cmd not in {"install", "sync", "update"}:
        parser.error(f"--dry-run is not supported by {cmd}")
    if options.refresh and cmd != "_skills":
        parser.error("--refresh is internal to skill installation")
    if cmd in {"help", "-h", "--help"}:
        _print_help()
        sys.exit()
    if cmd == "docs":
        _print_docs()
        sys.exit()
    if cmd not in _COMMANDS and cmd not in {"_skills", "_dotfiles"}:
        _print_error(f"unknown command: {cmd}. available: {', '.join(_COMMANDS)}")
        sys.exit(1)
    try:
        if cmd == "self-update":
            self_update()
        else:
            if not CONFIG_FILE.exists():
                raise ConfigNotFoundError(CONFIG_FILE, CONFIG_EXAMPLE_FILE)
            overrides = read_toml(CONFIG_FILE)
            normalized_overrides, warnings = normalize_config(overrides)
            for warning in warnings:
                _print_warning(warning)
            instance = Kaizen(normalized_overrides, options.features, options.dry_run)
            if cmd == "_skills":
                instance._install_skills(instance._features(), update=options.refresh)
            elif cmd == "_dotfiles":
                instance._apply_dotfiles()
            else:
                getattr(instance, cmd)()
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


if __name__ == "__main__":
    main()
