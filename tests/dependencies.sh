#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
KAIZEN_PATH="$PROJECT_DIR/kaizen.py" python3 <<'PY'
import importlib.util
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

path = Path(os.environ["KAIZEN_PATH"])
spec = importlib.util.spec_from_file_location("kaizen_dependencies_test", path)
kaizen = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = kaizen
spec.loader.exec_module(kaizen)


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def feature(name="sample", **data):
    return kaizen.Feature(kaizen.FEATURES_DIR / "tools.toml", name, data)


class DependenciesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        values = {
            "KAIZEN_DIR": self.root,
            "FEATURES_DIR": self.root / "features",
            "DOTFILES_DIR": self.root / "dotfiles",
            "CONFIG_FILE": self.root / "config.toml",
            "USER_DEPENDENCIES_FILE": self.root / "dependencies.toml",
            "USER_DATA_FILE": self.root / "dotfiles/.chezmoidata/99-user.toml",
            "MISE_CONFIG": self.root / "global-mise.toml",
            "BOOTSTRAP_CONFIG": self.root / "bootstrap.toml",
        }
        for name, value in values.items():
            patcher = patch.object(kaizen, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.instance = kaizen.Kaizen({})
        self.instance._os = "fedora"

    def test_user_dependency_validation(self):
        self.assertEqual(kaizen.load_user_dependencies(), {})
        for content, error in [
            ("script = true", ValueError),
            ('[tools]\nnode = 22', TypeError),
            ('[tools]\n"" = "22"', TypeError),
            ('[macos]\nbrew = "jq"', TypeError),
            ('[linux]\npacman = ["jq"]', ValueError),
            ('[tools', ValueError),
        ]:
            with self.subTest(content=content):
                write(kaizen.USER_DEPENDENCIES_FILE, content)
                with self.assertRaises(error):
                    kaizen.load_user_dependencies()
        write(kaizen.USER_DEPENDENCIES_FILE, '[tools]\nnode = "22"\n[macos]\nbrew = ["jq"]\n[macos.brew_args]\njq = ["--HEAD"]\n[linux]\napt = ["jq"]')
        self.assertEqual(kaizen.load_user_dependencies()["macos"]["brew_args"], {"jq": ["--HEAD"]})

    def test_shared_packages_resolve_aliases_and_deduplicate(self):
        features = [
            feature("core", packages=["fd", "fd"], package_names={"fd": {"dnf": "fd-find", "apt": "fd-find"}}, brew=["mole"]),
            feature("extra", packages=["fd-find", "jq"], brew=["jq"], flatpak=["dev.zed.Zed"]),
        ]
        dependencies = {"macos": {"brew": ["fd", "jq"], "cask": ["zed", "zed"]}, "linux": {"dnf": ["fd-find"]}}
        resolved = kaizen._resolve_packages(features, dependencies)
        self.assertEqual(resolved["macos"], {"brew": ["fd", "mole", "jq"], "cask": ["zed"]})
        self.assertEqual(resolved["linux"], {"dnf": ["fd-find", "jq"], "apt": ["fd-find", "jq"], "flatpak": ["dev.zed.Zed"]})
        self.assertEqual(features[0].data["packages"], ["fd", "fd"])

    def test_package_conflicts_fail_before_commands_or_writes(self):
        first = feature("first", packages=["fd"], package_names={"fd": {"dnf": "fd-find"}})
        cases = [
            ([first, feature("second", package_names={"fd": {"dnf": "other-fd"}})], {}),
            ([first, feature("second", package_names={"other": {"brew": "fd-find"}})], {}),
            ([first], {"linux": {"dnf": ["fd"]}}),
            ([first], {"macos": {"brew": ["fd"], "brew_args": {"fd": ["--HEAD"]}}}),
        ]
        for features, dependencies in cases:
            with self.subTest(features=features, dependencies=dependencies), patch.object(
                self.instance, "_features", return_value=features
            ), patch.object(kaizen, "load_user_dependencies", return_value=dependencies), patch.object(kaizen.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    self.instance.install()
                run.assert_not_called()
                self.assertFalse(kaizen.BOOTSTRAP_CONFIG.exists())
                self.assertFalse(kaizen.MISE_CONFIG.exists())

    def test_feature_schema_validation(self):
        for data in [
            {"packages": "jq"}, {"packages": [False]}, {"packages": [""]},
            {"package_names": []}, {"package_names": {"fd": "fd-find"}},
            {"package_names": {"fd": {"apt": ""}}},
            {"package_names": {"fd": {"pacman": "fd"}}},
            {"archive": "true"}, {"platforms": []}, {"post_install": "../hook"},
            {"dotfiles": ["/tmp/config"]}, {"dotfiles": ["dotfiles/../secret"]},
            {"dotfiles": ["dotfiles"]}, {"bootstrap": []},
        ]:
            with self.subTest(data=data), self.assertRaises((ValueError, TypeError)):
                feature(**data).active_on("macos")

    def test_discovery_and_explicit_selection(self):
        write(kaizen.FEATURES_DIR / "tools.toml", '[core]\npackages = ["jq"]\n[shell]\ntools = {carapace = "latest"}\n[archived]\narchive = true\n[maconly]\nplatforms = ["macos"]\n[fedora]\nplatforms = ["linux"]\ndistributions = ["fedora"]\n')
        self.assertEqual([f.name for f in kaizen.discover_features("fedora")], ["core", "fedora", "shell"])
        self.assertEqual([f.name for f in kaizen.discover_features("ubuntu", ["shell", "core", "core"])], ["core", "shell"])
        for names in [["missing"], ["archived"], ["maconly"]]:
            with self.subTest(names=names), self.assertRaises(ValueError):
                kaizen.discover_features("fedora", names)
        write(kaizen.FEATURES_DIR / "editor.toml", '[broken]\npost_install = "features/hooks/missing.py"')
        self.assertEqual([f.name for f in kaizen.discover_features("fedora", ["core"])], ["core"])
        with self.assertRaises(FileNotFoundError):
            kaizen.discover_features("fedora")
        write(kaizen.FEATURES_DIR / "editor.toml", '[core]')
        with self.assertRaisesRegex(ValueError, "duplicate feature"):
            kaizen.discover_features("fedora", ["core"])

    def test_cli_repeated_features_help_and_invalid_selections(self):
        home = self.root / "home"
        write(home / ".config/kaizen/config.toml", "")
        script = self.root / "kaizen.py"
        write(script, path.read_text())
        write(kaizen.FEATURES_DIR / "tools.toml", '[first]\n[second]\n[archived]\narchive = true')
        environment = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")}
        command = [sys.executable, str(script)]
        result = subprocess.run([*command, "status", "--feature", "first", "--feature", "second", "--feature", "first"], env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("tools/first"), 1)
        self.assertIn("tools/second", result.stdout)
        self.assertNotIn("tools/archived", result.stdout)
        for name in ["unknown", "archived"]:
            result = subprocess.run([*command, "sync", "--feature", name, "--dry-run"], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn(name, result.stderr)
        result = subprocess.run([*command, "capture", "--feature", "first"], env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not supported", result.stderr)
        result = subprocess.run([*command, "--help"], env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("--feature", result.stdout)
        self.assertFalse((home / ".config/kaizen/bootstrap.toml").exists())

    def test_linux_only_declares_one_native_manager(self):
        sample = feature(packages=["fd"], package_names={"fd": {"dnf": "fd-find", "apt": "fd-find"}}, flatpak=["dev.zed.Zed"])
        for os_name, manager in [("ubuntu", "apt"), ("fedora", "dnf"), ("fedora-asahi-remix", "dnf")]:
            self.instance._os = os_name
            config = self.instance._bootstrap_config([sample], {}, "sync", dotfiles=False)
            self.assertEqual(config["bootstrap"]["packages"], {f"{manager}:fd-find": "latest", "flatpak:dev.zed.Zed": "latest"})
        self.instance._os = "unknown"
        with self.assertRaisesRegex(ValueError, "unsupported native"):
            self.instance._bootstrap_config([sample], {}, "sync", dotfiles=False)

    def test_homebrew_flags_taps_casks_and_scoped_upgrade(self):
        self.instance._os = "macos"
        sample = feature(taps=["tools/tap"], brew=["emacs-plus@32"], brew_args={"emacs-plus@32": ["--with-xwidgets", "--build-from-source"]}, cask=["ghostty"])
        with patch.object(kaizen, "_find_homebrew", return_value="/fake path/brew"):
            config = self.instance._bootstrap_config([sample], {}, "update", dotfiles=False)
        commands = [shlex.split(c) for c in config["bootstrap"]["hooks"]["pre-packages"]]
        self.assertEqual(commands[0], ["/fake path/brew", "tap", "tools/tap"])
        self.assertIn(["/fake path/brew", "install", "--yes", "emacs-plus@32", "--with-xwidgets", "--build-from-source"], commands)
        self.assertIn(["/fake path/brew", "upgrade", "--yes", "emacs-plus@32", "--with-xwidgets", "--build-from-source"], commands)
        self.assertIn(["/fake path/brew", "upgrade", "--yes", "--cask", "ghostty"], commands)
        self.assertNotIn(["/fake path/brew", "upgrade", "--yes"], commands)

    def test_tools_overrides_roundtrip_and_empty_global_config(self):
        sample = feature(tools={"node": "20", "python": "3.11"})
        dependencies = {"tools": {"node": "22", "tool name": 'v"quoted'}}
        config = self.instance._bootstrap_config([sample], dependencies, "sync", dotfiles=False)
        kaizen.write_toml(config, kaizen.BOOTSTRAP_CONFIG)
        self.assertEqual(kaizen.read_toml(kaizen.BOOTSTRAP_CONFIG), config)
        self.instance._generate_mise_config([sample], dependencies)
        self.assertEqual(kaizen.read_toml(kaizen.MISE_CONFIG)["tools"], config["tools"])
        self.instance._generate_mise_config([], {})
        self.assertFalse(kaizen.MISE_CONFIG.exists())

    def test_bootstrap_merging_conflicts_and_reserved_fields(self):
        first = feature("one", bootstrap={"macos": {"dock": {"tilesize": 32}}})
        second = feature("two", bootstrap={"macos": {"dock": {"autohide": True}}})
        config = self.instance._bootstrap_config([first, second], {}, "sync", dotfiles=False)
        self.assertEqual(config["bootstrap"]["macos"]["dock"], {"tilesize": 32, "autohide": True})
        second.data["bootstrap"]["macos"]["dock"]["tilesize"] = 48
        with self.assertRaisesRegex(ValueError, "conflicting bootstrap"):
            self.instance._bootstrap_config([first, second], {}, "sync", dotfiles=False)
        for key in ["packages", "hooks"]:
            with self.assertRaisesRegex(ValueError, "generated by Kaizen"):
                self.instance._bootstrap_config([feature(bootstrap={key: {}})], {}, "sync", dotfiles=False)

    def test_tasks_preserve_skills_hooks_dotfiles_order_and_action(self):
        write(self.root / "features/hooks/sample.py", "")
        write(self.root / "dotfiles/dot_config/editor/config", "")
        sample = feature(skills=["owner/repo@skill"], post_install="features/hooks/sample.py", dotfiles=["dotfiles/dot_config/editor"])
        self.instance._selected = ["sample"]
        for action in ["sync", "update"]:
            config = self.instance._bootstrap_config([sample], {}, action, dotfiles=True)
            commands = [shlex.split(c) for c in config["tasks"]["bootstrap"]["run"]]
            self.assertEqual(commands[0][2:5], ["_skills", "--feature", "sample"])
            self.assertEqual("--refresh" in commands[0], action == "update")
            self.assertEqual(commands[1][-2:], ["fedora", action])
            self.assertEqual(commands[2][2:5], ["_dotfiles", "--feature", "sample"])
            self.assertNotIn("--force", commands[2])
        with self.assertRaisesRegex(ValueError, "different sources"):
            self.instance._bootstrap_config([sample, feature("other", skills=["other/repo@skill"])], {}, "sync", dotfiles=False)

    def test_selected_dotfiles_are_explicit_shared_and_fail_closed(self):
        self.instance._selected = ["one", "two"]
        write(self.root / "dotfiles/dot_config/shared/config", "")
        selected = [feature("one", dotfiles=["dotfiles/dot_config/shared"]), feature("two", dotfiles=["dotfiles/dot_config/shared"])]
        sources = self.instance._selected_dotfiles(selected)
        self.assertEqual(sources.count(str(self.root / "dotfiles/dot_config/shared")), 1)
        self.assertEqual(self.instance._dotfiles_command([feature()]), [])
        with self.assertRaises(FileNotFoundError):
            self.instance._dotfiles_command([feature(dotfiles=["dotfiles/missing"])])
        (self.root / "dotfiles/escape").symlink_to(self.root)
        with self.assertRaises(ValueError):
            self.instance._dotfiles_command([feature(dotfiles=["dotfiles/escape"])])
        self.instance._selected = None
        self.assertEqual(self.instance._dotfiles_command([]), ["chezmoi", "apply", "--source", str(kaizen.DOTFILES_DIR)])

    def test_install_and_update_never_apply_dotfiles(self):
        with patch.object(self.instance, "_execute") as execute:
            self.instance.install()
            execute.assert_called_once_with("sync", dotfiles=False)
            execute.reset_mock()
            self.instance.update()
            execute.assert_called_once_with("update", dotfiles=False)
            execute.reset_mock()
            self.instance.sync()
            execute.assert_called_once_with("sync", dotfiles=True)

    def test_dry_run_does_not_write_persistent_configuration_or_run_hooks(self):
        self.instance._dry_run = True
        self.instance._selected = ["sample"]
        sample = feature(post_install="features/hooks/sample.py")
        capability = subprocess.CompletedProcess([], 0, "--upgrade", "")
        with patch.object(self.instance, "_features", return_value=[sample]), patch.object(kaizen.shutil, "which", return_value="/fake/mise"), patch.object(kaizen.subprocess, "run", return_value=capability), patch.object(kaizen, "_run_mise") as run:
            self.instance.sync()
            config, arguments = run.call_args.args
            self.assertIn("--dry-run", arguments)
            self.assertFalse(config.exists())
        for path in [kaizen.MISE_CONFIG, kaizen.BOOTSTRAP_CONFIG, kaizen.USER_DATA_FILE]:
            self.assertFalse(path.exists(), path)

    def test_execution_writes_selected_configs_and_scopes_update(self):
        sample = feature(tools={"node": "22"})
        self.instance._selected = ["sample"]
        capability = subprocess.CompletedProcess([], 0, "--upgrade", "")
        with patch.object(self.instance, "_features", return_value=[sample]), patch.object(kaizen.shutil, "which", return_value="/fake/mise"), patch.object(kaizen.subprocess, "run", return_value=capability), patch.object(kaizen, "_run_mise") as run:
            self.instance.update()
            run.assert_called_once_with(kaizen.BOOTSTRAP_CONFIG, ["bootstrap", "--update", "--upgrade"])
        self.assertEqual(kaizen.read_toml(kaizen.MISE_CONFIG)["tools"], {"node": "22"})
        self.assertEqual(kaizen.read_toml(kaizen.BOOTSTRAP_CONFIG)["tools"], {"node": "22"})
        self.assertFalse(kaizen.USER_DATA_FILE.exists())

    def test_mise_and_native_prerequisites_fail_before_writes(self):
        with patch.object(self.instance, "_features", return_value=[]), patch.object(kaizen.shutil, "which", return_value=None):
            with self.assertRaises(kaizen.DependencyNotFoundError):
                self.instance.install()
        with patch.object(self.instance, "_features", return_value=[]), patch.object(kaizen.shutil, "which", return_value="/fake/mise"), patch.object(kaizen.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "")):
            with self.assertRaisesRegex(kaizen.DependencyNotFoundError, "bootstrap"):
                self.instance.install()
        sample = feature(packages=["jq"])
        with patch.object(self.instance, "_features", return_value=[sample]), patch.object(kaizen.shutil, "which", side_effect=lambda name: "/fake/mise" if name == "mise" else None), patch.object(kaizen.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "--upgrade", "")):
            with self.assertRaisesRegex(kaizen.ExecutableNotFoundError, "dnf"):
                self.instance.install()
        self.assertFalse(kaizen.BOOTSTRAP_CONFIG.exists())

    def test_flatpak_missing_remote_fails_without_writing_configs(self):
        sample = feature(flatpak=["dev.zed.Zed"])
        results = [subprocess.CompletedProcess([], 0, "--upgrade", ""), subprocess.CompletedProcess([], 0, "other-remote\n", "")]
        with patch.object(self.instance, "_features", return_value=[sample]), patch.object(kaizen.shutil, "which", return_value="/fake/tool"), patch.object(kaizen.subprocess, "run", side_effect=results):
            with self.assertRaisesRegex(ValueError, "system-wide flathub"):
                self.instance.install()
        self.assertFalse(kaizen.BOOTSTRAP_CONFIG.exists())
        self.assertFalse(kaizen.MISE_CONFIG.exists())

    def test_bump_preserves_user_versions_archived_features_and_other_metadata(self):
        catalog = kaizen.FEATURES_DIR / "tools.toml"
        write(catalog, '[sample]\npackages = ["jq"]\ndotfiles = ["dotfiles/config"]\ntools = {node = "20", python = "3.11"}\n[archived]\narchive = true\ntools = {rust = "1.80"}')
        write(kaizen.MISE_CONFIG, '[tools]\nnode = "22"\npython = "3.12"\nrust = "1.81"')
        self.instance._capture_mise_versions(kaizen.discover_features("fedora"), {"node"})
        data = kaizen.read_toml(catalog)
        self.assertEqual(data["sample"]["tools"], {"node": "20", "python": "3.12"})
        self.assertEqual(data["sample"]["packages"], ["jq"])
        self.assertEqual(data["archived"]["tools"], {"rust": "1.80"})

    def test_user_overlay_does_not_follow_old_symlink(self):
        original = self.root / "original.toml"
        write(original, 'layout = "saved"')
        kaizen.USER_DATA_FILE.parent.mkdir(parents=True)
        kaizen.USER_DATA_FILE.symlink_to(original)
        self.instance._user_data = {"layout": "colemak"}
        self.instance._write_user_data()
        self.assertFalse(kaizen.USER_DATA_FILE.is_symlink())
        self.assertEqual(original.read_text(), 'layout = "saved"')
        self.assertEqual(kaizen.read_toml(kaizen.USER_DATA_FILE), {"layout": "colemak"})

    @unittest.skipUnless(shutil.which("mise") and shutil.which("chezmoi"), "requires mise and chezmoi")
    def test_real_mise_applies_only_selected_dotfiles_after_hook_in_sandbox(self):
        home = self.root / "home"
        home.mkdir()
        write(kaizen.DOTFILES_DIR / "dot_config/selected/config", "selected\n")
        write(kaizen.DOTFILES_DIR / "dot_config/desktop/config", "desktop\n")
        write(kaizen.DOTFILES_DIR / "private_Library/ignored/config", "ignored\n")
        write(kaizen.DOTFILES_DIR / ".chezmoiignore", "Library/\n")
        write(kaizen.DOTFILES_DIR / ".chezmoiremove", "obsolete\n")
        write(home / "obsolete", "keep\n")
        write(home / ".config/desktop/config", "user-owned\n")
        write(self.root / "mise.toml", '[tools]\n"project-tool-must-not-install" = "latest"')
        write(self.root / ".tool-versions", "project-tool-must-not-install latest\n")
        write(self.root / "kaizen.py", path.read_text())
        write(home / ".config/kaizen/config.toml", "")
        hook = self.root / "features/hooks/sample.py"
        marker = self.root / "order"
        binary = self.root / "bin/skills"
        write(binary, f'#!/bin/sh\nif [ "$1" = list ]; then printf "[]"; else printf "skill\\n" >> {shlex.quote(str(marker))}; fi\n')
        binary.chmod(0o755)
        write(hook, f'from pathlib import Path\np = Path({str(marker)!r})\nassert p.read_text() == "skill\\n"\np.write_text(p.read_text() + "hook\\n")\n')
        write(kaizen.FEATURES_DIR / "tools.toml", '[sample]\nskills = ["owner/repo@skill"]\ndotfiles = ["dotfiles/dot_config/selected", "dotfiles/private_Library/ignored"]\npost_install = "features/hooks/sample.py"\n[desktop]\ndotfiles = ["dotfiles/dot_config/desktop"]\ntools = {"nonexistent-tool-must-not-install" = "latest"}\n')
        write(home / ".config/mise/config.toml", '[tools]\n"unrelated-tool-must-not-install" = "latest"')
        self.instance._selected = ["sample"]
        with patch.dict(os.environ, {"PATH": str(binary.parent) + os.pathsep + os.environ["PATH"], "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "XDG_DATA_HOME": str(home / ".local/share"), "XDG_CACHE_HOME": str(home / ".cache"), "XDG_STATE_HOME": str(home / ".local/state")}):
            self.instance.sync()
        self.assertEqual(marker.read_text(), "skill\nhook\n")
        self.assertEqual((home / ".config/selected/config").read_text(), "selected\n")
        self.assertEqual((home / ".config/desktop/config").read_text(), "user-owned\n")
        self.assertEqual((home / "obsolete").read_text(), "keep\n")
        self.assertFalse((home / "Library/ignored").exists())
        self.assertIn("unrelated-tool", (home / ".config/mise/config.toml").read_text())


unittest.main()
PY
