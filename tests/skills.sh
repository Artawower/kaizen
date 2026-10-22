#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
KAIZEN_PATH="$PROJECT_DIR/kaizen.py" python3 <<'PY'
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

path = Path(os.environ["KAIZEN_PATH"])
spec = importlib.util.spec_from_file_location("kaizen", path)
kaizen = importlib.util.module_from_spec(spec)
sys.modules["kaizen"] = kaizen
spec.loader.exec_module(kaizen)

PACKAGE = "dietrichgebert/ponytail@ponytail"
SKILLS = "/fake tools/skills"


def feature(packages=None):
    return kaizen.Feature(path.parent / "features/tools.toml", "ai", {
        "skills": [PACKAGE] if packages is None else packages,
    })


def result(stdout="", returncode=0):
    return subprocess.CompletedProcess([], returncode, stdout, "")


class SkillsTests(unittest.TestCase):
    def setUp(self):
        self.instance = object.__new__(kaizen.Kaizen)

    def test_catalog_declares_requested_skills_and_cli(self):
        catalog = tomllib.loads((path.parent / "features/tools.toml").read_text())
        expected = {
            PACKAGE,
            "mattpocock/skills@retro",
            "mattpocock/skills@grill-me",
            "mattpocock/skills@grill-with-docs",
            "microsoft/playwright-cli@playwright-cli",
        }
        self.assertTrue(expected.issubset(catalog["ai"]["skills"]))
        self.assertIn("npm:skills", catalog["ai"]["tools"])
        self.assertTrue(kaizen.Feature(path.parent / "features/tools.toml", "ai", catalog["ai"]).active_on("macos"))

    def test_invalid_inventory_is_rejected(self):
        for packages in ["not a list", [1], [""], ["--all"], ["owner/repo"], ["owner/repo@skill extra"]]:
            with self.subTest(packages=packages):
                with self.assertRaises((TypeError, ValueError)):
                    feature(packages).active_on("macos")

    def test_install_is_global_noninteractive_and_deduplicated(self):
        with patch.object(kaizen.shutil, "which", return_value=SKILLS), patch.object(
            kaizen.subprocess, "run", side_effect=[result("[]"), result()]
        ) as run:
            self.instance._install_skills([feature(), feature()])
        self.assertEqual(run.call_args_list[0].args[0], [SKILLS, "list", "-g", "--json"])
        self.assertEqual(run.call_args_list[1].args[0], [SKILLS, "add", PACKAGE, "-g", "-y"])
        self.assertTrue(all(call.kwargs["check"] for call in run.call_args_list))
        self.assertTrue(all(call.kwargs["cwd"] == Path.home() for call in run.call_args_list))
        self.assertEqual(run.call_count, 2)

    def test_sync_skips_matching_source_but_not_a_different_source(self):
        for source, expected_calls in [("dietrichgebert/ponytail", 1), ("other/ponytail", 2), (None, 2)]:
            installed = json.dumps([{"name": "ponytail", "source": source}])
            with self.subTest(source=source), patch.object(
                kaizen.shutil, "which", return_value=SKILLS
            ), patch.object(kaizen.subprocess, "run", side_effect=[result(installed), result()]) as run:
                self.instance._install_skills([feature()])
                self.assertEqual(run.call_count, expected_calls)

    def test_update_reinstalls_only_declared_packages(self):
        installed = json.dumps([
            {"name": "ponytail", "source": "dietrichgebert/ponytail"},
            {"name": "unrelated", "source": "other/repo"},
        ])
        with patch.object(kaizen.shutil, "which", return_value=SKILLS), patch.object(
            kaizen.subprocess, "run", side_effect=[result(installed), result()]
        ) as run:
            self.instance._install_skills([feature()], update=True)
        self.assertEqual(run.call_args_list[-1].args[0], [SKILLS, "add", PACKAGE, "-g", "-y"])
        self.assertEqual(run.call_count, 2)

    def test_conflicting_sources_are_rejected_before_any_cli_call(self):
        with patch.object(kaizen.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "same skill name"):
                self.instance._install_skills([feature(), feature(["other/repo@ponytail"])])
        run.assert_not_called()

    def test_invalid_cli_output_stops_before_installing(self):
        for payload in ["not JSON", "{}", "[{}]", '[{"name": "ponytail", "source": []}]']:
            with self.subTest(payload=payload), patch.object(kaizen.shutil, "which", return_value=SKILLS), patch.object(
                kaizen.subprocess, "run", return_value=result(payload)
            ) as run:
                with self.assertRaises(ValueError):
                    self.instance._install_skills([feature()])
                self.assertEqual(run.call_count, 1)

    def test_empty_inventory_does_not_call_cli(self):
        with patch.object(kaizen.shutil, "which") as which, patch.object(kaizen.subprocess, "run") as run:
            self.instance._install_skills([feature([])])
        which.assert_not_called()
        run.assert_not_called()

    def test_missing_cli_is_an_explicit_skip(self):
        with patch.object(kaizen.shutil, "which", return_value=None), patch.object(
            kaizen.subprocess, "run"
        ) as run, patch.object(kaizen, "_print_warning") as warning:
            self.instance._install_skills([feature()])
        run.assert_not_called()
        warning.assert_called_once()
        self.assertIn("skills", warning.call_args.args[0])

    def test_fresh_mise_install_uses_mise_runtime_environment(self):
        with patch.object(kaizen.shutil, "which", side_effect=lambda name: "/fake/mise" if name == "mise" else None), patch.object(
            kaizen.subprocess, "run", side_effect=[result("/new/skills\n"), result("[]"), result()]
        ) as run:
            self.instance._install_skills([feature()])
        self.assertEqual(run.call_args_list[0].args[0], ["/fake/mise", "which", "skills"])
        self.assertEqual(run.call_args_list[1].args[0], ["/fake/mise", "exec", "--", "skills", "list", "-g", "--json"])
        self.assertEqual(run.call_args_list[2].args[0], ["/fake/mise", "exec", "--", "skills", "add", PACKAGE, "-g", "-y"])

    def test_mise_without_skills_is_an_explicit_skip(self):
        with patch.object(kaizen.shutil, "which", side_effect=lambda name: "/fake/mise" if name == "mise" else None), patch.object(
            kaizen.subprocess, "run", return_value=result(returncode=1)
        ) as run, patch.object(kaizen, "_print_warning") as warning:
            self.instance._install_skills([feature()])
        self.assertEqual(run.call_count, 1)
        warning.assert_called_once()

    def test_cli_errors_are_not_ignored(self):
        failure = subprocess.CalledProcessError(7, [SKILLS])
        for outcomes in [[failure], [result("[]"), failure]]:
            with self.subTest(outcomes=outcomes), patch.object(kaizen.shutil, "which", return_value=SKILLS), patch.object(
                kaizen.subprocess, "run", side_effect=outcomes
            ):
                with self.assertRaises(subprocess.CalledProcessError):
                    self.instance._install_skills([feature()])

    def test_archived_and_foreign_features_are_excluded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample.toml").write_text(
                f'[active]\nskills = ["{PACKAGE}"]\n'
                '[archived]\narchive = true\nskills = ["other/repo@archived"]\n'
                '[linux]\nplatforms = ["linux"]\nskills = ["other/repo@linux"]\n'
                '[fedora]\ndistributions = ["fedora"]\nplatforms = ["linux"]\nskills = ["other/repo@fedora"]\n'
            )
            with patch.object(kaizen, "FEATURES_DIR", root):
                features = kaizen.discover_features("macos")
            self.assertEqual([item.name for item in features], ["active"])
            with patch.object(kaizen, "FEATURES_DIR", root):
                features = kaizen.discover_features("ubuntu")
            self.assertEqual([item.name for item in features], ["active", "linux"])

    def test_update_runs_skills_after_mise_and_before_hooks(self):
        events = []
        self.instance._adapter = Mock()
        self.instance._adapter.update.side_effect = lambda: events.append("native")
        self.instance._os = "macos"
        self.instance._install_skills = lambda features, **kwargs: events.append(("skills", kwargs))
        self.instance._run_post_install = lambda item, action: events.append(("hook", action))
        with patch.object(kaizen, "discover_features", return_value=[feature()]), patch.object(
            kaizen.shutil, "which", return_value="/fake/mise"
        ), patch.object(kaizen.subprocess, "run", side_effect=lambda command, **kwargs: events.append(command)):
            self.instance.update()
        self.assertEqual(events, ["native", ["mise", "upgrade"], ("skills", {"update": True}), ("hook", "update")])


unittest.main()
PY
