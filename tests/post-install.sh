#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$repo_root" <<'PY'
import importlib.machinery
import importlib.util
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path
from unittest.mock import patch

root = Path(sys.argv[1])


def load(name, relative):
    loader = importlib.machinery.SourceFileLoader(name, str(root / relative))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


emacs = load("emacs_hook", "features/hooks/emacs/post_install.py")
keyboard = load("keyboard_hook", "features/hooks/keyboard/post_install.py")
anki = load("anki_hook", "features/hooks/language-learning/post_install.py")
codium = load("codium_hook", "features/hooks/vscodium/post_install.py")
services = load("services_hook", "dotfiles/dot_config/scripts/executable_setup-systemd-services")

catalog = tomllib.loads((root / "features/editor.toml").read_text())
assert emacs.emacs_formula() == catalog["emacs"]["package_names"]["emacs"]["brew"]

with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / "editor.toml"
    cases = [
        ('packages = ["emacs", "imagemagick"]\npackage_names = {emacs = {brew = "emacs-plus@32"}}\nbrew = ["tree-sitter"]', "emacs-plus@32"),
        ('brew = ["emacs-plus@31", "tree-sitter"]', "emacs-plus@31"),
        ('packages = ["emacs-plus"]', "emacs-plus"),
        ('packages = ["emacs"]\npackage_names = {emacs = {brew = "d12frosted/emacs-plus/emacs-plus@32"}}', "d12frosted/emacs-plus/emacs-plus@32"),
        ('packages = ["emacs"]\npackage_names = {emacs = {brew = "emacs-plus@32"}}\nbrew = ["emacs-plus@32"]', "emacs-plus@32"),
    ]
    with patch.object(emacs, "CATALOG_SOURCE", source):
        for declaration, expected in cases:
            source.write_text("[emacs]\n" + declaration)
            assert emacs.emacs_formula() == expected, declaration
        for declaration in ('brew = ["tree-sitter"]', 'packages = ["emacs"]\npackage_names = {emacs = {brew = "emacs-plus@32"}}\nbrew = ["emacs-plus@31"]'):
            source.write_text("[emacs]\n" + declaration)
            try:
                emacs.emacs_formula()
            except RuntimeError as error:
                assert str(error) == "macOS packages must declare exactly one Emacs Plus formula"
            else:
                raise AssertionError(f"invalid Emacs formula declaration accepted: {declaration}")

with patch.object(sys, "argv", ["post_install.py", "macos", "sync"]), patch.object(emacs, "install_terminal_colors"), patch.object(emacs, "install_application"), patch.object(emacs, "build_emacs_client"), patch.object(Path, "exists", return_value=True), patch.object(emacs.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="/fake/emacs\n")) as run:
    emacs.main()
    assert run.call_args_list[0].args[0] == ["brew", "--prefix", emacs.emacs_formula()]

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
