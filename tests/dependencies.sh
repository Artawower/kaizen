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
            kaizen.FEATURES_DIR / "sample" / "mise.toml",
            '[tools]\nnode = "20"\npython = "3.11"\n',
        )
        instance = object.__new__(kaizen.Kaizen)
        instance._generate_mise_config(
            [kaizen.Feature("sample")],
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
        feature_file = kaizen.FEATURES_DIR / "sample" / "mise.toml"
        write(feature_file, '[tools]\nnode = "20"\npython = "3.11"\n')
        write(kaizen.MISE_CONFIG, '[tools]\nnode = "22"\npython = "3.12"\n')
        instance = object.__new__(kaizen.Kaizen)
        instance._capture_mise_versions([kaizen.Feature("sample")], {"node"})
        tools = kaizen.read_toml(feature_file)["tools"]
        assert tools == {"node": "20", "python": "3.12"}


def test_sync_loads_dependencies_before_changes() -> None:
    events: list[object] = []
    instance = object.__new__(kaizen.Kaizen)
    instance._config = {}
    instance._os = "macos"
    original_parse = kaizen.parse_features
    original_load = kaizen.load_user_dependencies
    original_which = kaizen.shutil.which
    original_run = kaizen.subprocess.run
    kaizen.parse_features = lambda _: events.append("features") or []
    kaizen.load_user_dependencies = lambda: events.append("dependencies") or {}
    kaizen.shutil.which = lambda _: None
    kaizen.subprocess.run = lambda command, **_: events.append(command)
    instance._write_user_data = lambda: events.append("write")
    instance._install_user_packages = lambda _: events.append("packages")
    instance._generate_mise_config = lambda *_: events.append("mise")
    try:
        instance.sync()
    finally:
        kaizen.parse_features = original_parse
        kaizen.load_user_dependencies = original_load
        kaizen.shutil.which = original_which
        kaizen.subprocess.run = original_run
    assert events[:5] == ["features", "dependencies", "write", "packages", "mise"]


test_manifest_validation()
test_package_adapter_reuse()
test_user_tools_override_features()
test_bump_preserves_user_overrides()
test_sync_loads_dependencies_before_changes()
print("dependency tests passed")
PY
