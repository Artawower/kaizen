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


def test_install_does_not_apply_dotfiles() -> None:
    events: list[object] = []
    instance = object.__new__(kaizen.Kaizen)
    instance._config = {}
    original_parse = kaizen.parse_features
    original_load = kaizen.load_user_dependencies
    original_run = kaizen.subprocess.run
    kaizen.parse_features = lambda _: events.append("features") or []
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
        kaizen.parse_features = original_parse
        kaizen.load_user_dependencies = original_load
        kaizen.subprocess.run = original_run
    assert events[:4] == ["features", "dependencies", "write", "install"]
    assert events[4][0:2] == ["chezmoi", "apply"]


def test_dependency_workflow_runs_integrations() -> None:
    events: list[object] = []
    instance = object.__new__(kaizen.Kaizen)
    instance._os = "macos"
    feature = kaizen.Feature("sample")
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


test_manifest_validation()
test_package_adapter_reuse()
test_user_tools_override_features()
test_bump_preserves_user_overrides()
test_install_does_not_apply_dotfiles()
test_dependency_workflow_runs_integrations()
print("dependency tests passed")
PY
