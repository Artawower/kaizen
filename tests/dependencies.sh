#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
KAIZEN_PATH="$PROJECT_DIR/kaizen.py" python3 <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(os.environ["KAIZEN_PATH"])
spec = importlib.util.spec_from_file_location("kaizen_dependencies_test", path)
assert spec and spec.loader
kaizen = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = kaizen
spec.loader.exec_module(kaizen)


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def expect_error(
    path: Path, content: str, error_type: type[Exception], message: str
) -> None:
    write(path, content)
    try:
        kaizen.load_user_dependencies(path)
    except error_type as error:
        assert message in str(error), str(error)
        return
    raise AssertionError(f"expected {error_type.__name__}: {message}")


def test_manifest_validation() -> None:
    with tempfile.TemporaryDirectory() as directory:
        dependencies = Path(directory) / "dependencies.toml"
        assert kaizen.load_user_dependencies(dependencies) == {}
        write(
            dependencies,
            """[tools]
node = "22"

[macos]
brew = ["jq"]
cask = ["zed"]

[macos.brew_args]
jq = ["--HEAD"]

[linux]
dnf = ["jq"]
apt = ["jq"]
flatpak = ["dev.zed.Zed"]
""",
        )
        loaded = kaizen.load_user_dependencies(dependencies)
        assert loaded["tools"] == {"node": "22"}
        assert loaded["macos"]["brew"] == ["jq"]
        assert loaded["linux"]["apt"] == ["jq"]
        expect_error(dependencies, "script = true\n", ValueError, "unknown keys")
        expect_error(dependencies, "[tools]\nnode = 22\n", TypeError, "tools values")
        expect_error(dependencies, '[tools]\n"" = "22"\n', TypeError, "tools values")
        expect_error(dependencies, "[macos]\nbrew = \"jq\"\n", TypeError, "macos.brew")
        expect_error(dependencies, "[linux]\npacman = [\"jq\"]\n", ValueError, "pacman")
        expect_error(dependencies, "[tools\n", ValueError, str(dependencies))


def test_package_adapter_reuse() -> None:
    class RecordingAdapter:
        def __init__(self) -> None:
            self.calls: list[dict[str, object]] = []

        def install(self, dependencies: dict[str, object]) -> None:
            self.calls.append(dependencies)

    instance = object.__new__(kaizen.Kaizen)
    instance._os = "macos"
    instance._adapter = RecordingAdapter()
    dependencies = {"macos": {"brew": ["jq"]}, "tools": {"node": "22"}}
    instance._install_user_packages(dependencies)
    instance._install_user_packages({"tools": {"node": "22"}})
    assert instance._adapter.calls == [dependencies]


def test_user_tools_override_features() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        kaizen.KAIZEN_DIR = root
        kaizen.FEATURES_DIR = root / "features"
        kaizen.MISE_CONFIG = root / "mise.toml"
        write(
            kaizen.FEATURES_DIR / "editor.toml",
            '[sample]\ntools = { node = "20", python = "3.11" }\n',
        )
        instance = object.__new__(kaizen.Kaizen)
        instance._generate_mise_config(
            kaizen.discover_features("macos"),
            {
                "tools": {
                    "node": "22",
                    "go": "latest",
                    "tool name": 'v"quoted',
                }
            },
        )
        tools = kaizen.read_toml(kaizen.MISE_CONFIG)["tools"]
        assert tools == {
            "node": "22",
            "python": "3.11",
            "go": "latest",
            "tool name": 'v"quoted',
        }
        instance._generate_mise_config([], {})
        assert not kaizen.MISE_CONFIG.exists()


def test_bump_preserves_user_overrides() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        kaizen.KAIZEN_DIR = root
        kaizen.FEATURES_DIR = root / "features"
        kaizen.MISE_CONFIG = root / "mise.toml"
        feature_file = kaizen.FEATURES_DIR / "editor.toml"
        write(feature_file, '[sample]\nbrew = ["jq"]\ntools = { node = "20", python = "3.11" }\n\n[second]\ntools = { go = "1.21" }\n\n[archived]\narchive = true\ntools = { rust = "1.80" }\n')
        write(kaizen.MISE_CONFIG, '[tools]\nnode = "22"\npython = "3.12"\ngo = "1.22"\nrust = "1.81"\n')
        instance = object.__new__(kaizen.Kaizen)
        instance._capture_mise_versions(kaizen.discover_features("macos"), {"node"})
        catalog = kaizen.read_toml(feature_file)
        assert catalog["sample"]["tools"] == {"node": "20", "python": "3.12"}
        assert catalog["sample"]["brew"] == ["jq"]
        assert catalog["second"]["tools"] == {"go": "1.22"}
        assert catalog["archived"] == {"archive": True, "tools": {"rust": "1.80"}}
        assert "[sample.tools]" not in feature_file.read_text()


def test_install_does_not_apply_dotfiles() -> None:
    events: list[object] = []
    instance = object.__new__(kaizen.Kaizen)
    instance._os = "macos"
    original_parse = kaizen.discover_features
    original_load = kaizen.load_user_dependencies
    original_run = kaizen.subprocess.run
    original_which = kaizen.shutil.which
    kaizen.shutil.which = lambda _: "/tmp/chezmoi"
    kaizen.discover_features = lambda _: events.append("features") or []
    kaizen.load_user_dependencies = lambda: events.append("dependencies") or {}
    kaizen.subprocess.run = lambda command, **_: events.append(command)
    instance._write_user_data = lambda: events.append("write")
    instance._install_dependencies = lambda *_: events.append("install")
    try:
        instance.install()
        assert events == ["features", "dependencies", "install"]
        events.clear()
        instance.sync()
    finally:
        kaizen.discover_features = original_parse
        kaizen.load_user_dependencies = original_load
        kaizen.subprocess.run = original_run
        kaizen.shutil.which = original_which
    assert events[:4] == ["features", "dependencies", "write", "install"]
    assert events[4][0:2] == ["chezmoi", "apply"]
    assert "--force" not in events[4]


def test_dependency_workflow_runs_integrations() -> None:
    events: list[object] = []
    instance = object.__new__(kaizen.Kaizen)
    instance._os = "macos"
    feature = kaizen.Feature(kaizen.FEATURES_DIR / "editor.toml", "sample", {})
    original_which = kaizen.shutil.which
    original_run = kaizen.subprocess.run
    kaizen.shutil.which = lambda _: "/tmp/mise"
    kaizen.subprocess.run = lambda command, **_: events.append(command)
    instance._install_packages = lambda item: events.append(("packages", item))
    instance._install_user_packages = lambda _: events.append("user packages")
    instance._generate_mise_config = lambda *_: events.append("mise config")
    instance._run_post_install = lambda item, action: events.append((item, action))
    try:
        instance._install_dependencies([feature], {})
    finally:
        kaizen.shutil.which = original_which
        kaizen.subprocess.run = original_run
    assert events == [
        ("packages", feature),
        "user packages",
        "mise config",
        ["mise", "install", "--jobs=1"],
        (feature, "sync"),
    ]
    assert "install" in kaizen._COMMANDS


def test_failures_stop_workflow() -> None:
    from unittest.mock import patch
    import subprocess

    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "editor.toml"
        write(path, "[sample\n")
        try:
            kaizen.load_toml(path)
        except ValueError:
            pass
        else:
            raise AssertionError("malformed feature manifest accepted")

        with patch.object(kaizen.shutil, "which", return_value="/tmp/tool"):
            with patch.object(kaizen.subprocess, "run", side_effect=subprocess.CalledProcessError(2, ["sample"])) as run:
                try:
                    kaizen.Brew()._run(["sample"])
                except subprocess.CalledProcessError:
                    pass
                else:
                    raise AssertionError("native command failure ignored")
                assert run.call_args.kwargs["check"] is True

        instance = object.__new__(kaizen.Kaizen)
        with patch.object(kaizen.shutil, "which", return_value=None):
            with patch.object(instance, "_write_user_data") as write_data:
                try:
                    instance.sync()
                except kaizen.DependencyNotFoundError:
                    pass
                else:
                    raise AssertionError("sync without chezmoi accepted")
                write_data.assert_not_called()

        kaizen.MISE_CONFIG = Path(directory) / "mise.toml"
        write(kaizen.MISE_CONFIG, '[tools]\nnode = "latest"\n')
        instance._os = "linux"
        instance._install_user_packages = lambda _: None
        instance._generate_mise_config = lambda *_: None
        with patch.object(kaizen.shutil, "which", return_value=None):
            with patch.object(instance, "_run_post_install") as hook:
                try:
                    instance._install_dependencies([], {})
                except kaizen.DependencyNotFoundError:
                    pass
                else:
                    raise AssertionError("configured mise tools silently skipped")
                hook.assert_not_called()


def test_feature_discovery_filters_whole_recipe() -> None:
    from unittest.mock import Mock, patch

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        features = root / "features"
        catalogs = {
            "tiling": {
                "first": 'platforms = ["linux"]\ndistributions = ["fedora"]\ndnf = ["first"]\n',
                "second": 'platforms = ["linux"]\ndnf = ["second"]\n',
                "rift": 'platforms = ["macos"]\nbrew = ["rift"]\n',
            },
            "editor": {"archived": 'archive = true\n'},
            "system": {"shared": 'description = "Shared tools"\n'},
        }
        for category, entries in catalogs.items():
            sections = []
            for name, settings in entries.items():
                hook = f"features/hooks/{name}/post_install.py"
                sections.append(f'[{name}]\n{settings}tools = {{ {name} = "latest" }}\npost_install = "{hook}"\n')
                if name != "archived":
                    write(root / hook, 'raise RuntimeError("must be mocked")\n')
            write(features / f"{category}.toml", "\n".join(sections))
        user_data = {
            "shortcuts": [{"keys": [["h"], ["Left"]], "description": "Move left."}],
        }
        overlay = root / "dotfiles/.chezmoidata/99-user.toml"
        overlay.parent.mkdir(parents=True)
        original_config = root / "user.toml"
        original_config.write_text("unchanged\n")
        overlay.symlink_to(original_config)
        with (
            patch.object(kaizen, "KAIZEN_DIR", root),
            patch.object(kaizen, "FEATURES_DIR", features),
            patch.object(kaizen, "USER_DATA_FILE", overlay),
            patch.object(kaizen, "MISE_CONFIG", root / "mise.toml"),
            patch.object(kaizen, "detect_os", return_value="fedora"),
            patch.object(kaizen.shutil, "which", return_value="/tmp/tool"),
            patch.object(kaizen.subprocess, "run") as run,
        ):
            selected = kaizen.discover_features("fedora")
            names = {item.name for item in selected}
            assert names == {"first", "second", "shared"}
            assert {item.name for item in kaizen.discover_features("macos")} == {"rift", "shared"}
            assert {item.name for item in kaizen.discover_features("ubuntu")} == {"second", "shared"}
            instance = kaizen.Kaizen(user_data)
            instance._adapter = Mock()
            instance._write_user_data()
            assert not overlay.is_symlink()
            assert kaizen.read_toml(overlay) == user_data
            assert original_config.read_text() == "unchanged\n"
            instance._install_dependencies(selected, {})
            assert instance._adapter.install.call_count == len(selected)
            assert set(kaizen.read_toml(kaizen.MISE_CONFIG)["tools"]) == names
            instance.update()
            hooks = [
                call.args[0] for call in run.call_args_list
                if call.args[0][0] == sys.executable
            ]
            assert len(hooks) == 2 * len(selected)
            assert all(Path(command[1]).parent.name in names for command in hooks)
            assert all(command[2] == "fedora" for command in hooks)
            write(features / "editor.toml", '[archived]\narchive = "true"\n')
            try:
                kaizen.discover_features("fedora")
            except TypeError as error:
                assert "archive must be true or false" in str(error)
            else:
                raise AssertionError("invalid archive flag accepted")
            for config in ({"features": {"first": False}}, {"tiling": {"variant": "old"}}):
                try:
                    kaizen.normalize_config(config)
                except ValueError as error:
                    assert "no longer supported" in str(error)
                else:
                    raise AssertionError("obsolete feature selection silently ignored")



test_feature_discovery_filters_whole_recipe()
test_failures_stop_workflow()
test_manifest_validation()
test_package_adapter_reuse()
test_user_tools_override_features()
test_bump_preserves_user_overrides()
test_install_does_not_apply_dotfiles()
test_dependency_workflow_runs_integrations()
print("dependency tests passed")
PY
