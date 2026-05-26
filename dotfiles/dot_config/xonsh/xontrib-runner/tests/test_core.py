import json
from pathlib import Path

import pytest

from xontrib.runner.adapters.cargo import CargoAdapter
from xontrib.runner.adapters.justfile import JustfileAdapter
from xontrib.runner.adapters.makefile import MakefileAdapter
from xontrib.runner.adapters.npm import NodeAdapter
from xontrib.runner.core import Task, TaskCatalog


def test_node_adapter_npm(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps({"scripts": {"build": "tsc", "test": "jest"}}))
    tasks = NodeAdapter().tasks(tmp_path)
    assert {t.name for t in tasks} == {"build", "test"}
    assert all(t.provider == "npm" for t in tasks)
    assert all(t.command.startswith("npm run") for t in tasks)


def test_node_adapter_detects_bun(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps({"scripts": {"dev": "bun dev"}}))
    (tmp_path / "bun.lockb").touch()
    tasks = NodeAdapter().tasks(tmp_path)
    assert tasks[0].provider == "bun"
    assert tasks[0].command == "bun run dev"


def test_node_adapter_detects_pnpm(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps({"scripts": {"start": "node ."}}))
    (tmp_path / "pnpm-lock.yaml").touch()
    tasks = NodeAdapter().tasks(tmp_path)
    assert tasks[0].provider == "pnpm"


def test_makefile_adapter(tmp_path):
    (tmp_path / "Makefile").write_text("build:\n\tgo build\ntest:\n\tgo test\n.PHONY: build\n")
    tasks = MakefileAdapter().tasks(tmp_path)
    names = {t.name for t in tasks}
    assert {"build", "test"}.issubset(names)
    assert all(t.command.startswith("make") for t in tasks)


def test_cargo_adapter(tmp_path):
    (tmp_path / "Cargo.toml").write_text('[package]\nname = "foo"')
    tasks = CargoAdapter().tasks(tmp_path)
    names = {t.name for t in tasks}
    assert {"build", "test", "run", "check"}.issubset(names)
    assert all(t.provider == "cargo" for t in tasks)


def test_find_root_walks_up(tmp_path):
    (tmp_path / "package.json").write_text("{}")
    subdir = tmp_path / "src" / "components"
    subdir.mkdir(parents=True)
    root = NodeAdapter().find_root(subdir)
    assert root == tmp_path


def test_find_root_returns_none(tmp_path):
    assert NodeAdapter().find_root(tmp_path) is None


def test_catalog_deduplicates(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps({"scripts": {"build": "tsc"}}))
    catalog = TaskCatalog([NodeAdapter(), NodeAdapter()])
    tasks = catalog.collect(tmp_path)
    assert len([t for t in tasks if t.name == "build"]) == 1


def test_catalog_priority_order(tmp_path):
    (tmp_path / "justfile").write_text("")
    (tmp_path / "package.json").write_text(json.dumps({"scripts": {"build": "tsc"}}))
    from unittest.mock import patch
    with patch.object(JustfileAdapter, "tasks", return_value=[
        Task("build", "just build", "just", tmp_path)
    ]):
        catalog = TaskCatalog([JustfileAdapter(), NodeAdapter()])
        tasks = catalog.collect(tmp_path)
    builds = [t for t in tasks if t.name == "build"]
    assert builds[0].provider == "just"
