#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$repo_root" <<'PY'
import importlib.machinery
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

root = Path(sys.argv[1])


def load(name, relative):
    loader = importlib.machinery.SourceFileLoader(name, str(root / relative))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


keyboard = load("keyboard_hook", "features/keyboard/post_install.py")
anki = load("anki_hook", "features/language-learning/post_install.py")
codium = load("codium_hook", "features/vscodium/post_install.py")
services = load("services_hook", "dotfiles/dot_config/scripts/executable_setup-systemd-services")

for os_name in ("macos", "linux", "fedora", "fedora-asahi-remix", "ubuntu", "debian"):
    with patch.object(sys, "argv", ["post_install.py", os_name, "sync"]):
        with patch.object(keyboard, "configure_hid_apple") as configure:
            keyboard.main()
            assert configure.call_count == (os_name != "macos"), os_name

        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(Path, "home", return_value=home):
                with patch.object(anki, "install_addon") as install:
                    assert anki.main() == 0
                    expected = [anki.ANKI_CONNECT_ADDON_ID]
                    if os_name != "macos":
                        expected.append(anki.LINUX_TTS_ADDON_ID)
                    assert [call.args[0] for call in install.call_args_list] == expected
                    paths = anki.get_addons_directories(os_name)
                    assert len(paths) == 1 and paths[0].is_dir()
                    assert all(home in path.parents for path in paths)

    with patch.object(codium.shutil, "which", side_effect=lambda name: "/bin/flatpak" if name == "flatpak" else None):
        with patch.object(Path, "is_file", return_value=False):
            with patch.object(codium.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
                runner = codium.resolve_codium_runner(os_name)
                if os_name == "macos":
                    assert runner is None
                    run.assert_not_called()
                else:
                    assert runner == ["flatpak", "run", "com.vscodium.codium"]
                    assert run.call_args.args[0] == ["flatpak", "info", "com.vscodium.codium"]

with patch.object(services.subprocess, "run") as run:
    services.install_titdb_service()
    calls = run.call_args_list
    assert len(calls) == 5
    assert calls[0].args[0] == ["sudo", "tee", "/etc/systemd/system/titdb.service"]
    assert calls[0].kwargs["input"] == services.TITDB_UNIT.encode()
    assert calls[0].kwargs["stdout"] == subprocess.DEVNULL
    assert all(call.kwargs["check"] is True for call in calls)

print("Post-install OS and systemd regression tests passed")
PY
