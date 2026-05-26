from __future__ import annotations

import json
from pathlib import Path

from ..core import Task
from .base import BaseAdapter

_LOCKFILE_PM = {
    "bun.lockb": "bun",
    "bun.lock": "bun",
    "pnpm-lock.yaml": "pnpm",
    "yarn.lock": "yarn",
}


class NodeAdapter(BaseAdapter):
    marker = "package.json"

    def _detect_pm(self, root: Path) -> str:
        for lockfile, pm in _LOCKFILE_PM.items():
            if (root / lockfile).exists():
                return pm
        return "npm"

    def tasks(self, root: Path) -> list[Task]:
        try:
            data = json.loads((root / "package.json").read_text())
        except (OSError, json.JSONDecodeError):
            return []
        pm = self._detect_pm(root)
        scripts = data.get("scripts", {})
        return [
            Task(name=name, command=f"{pm} run {name}", provider=pm, root=root)
            for name in scripts
        ]
