from __future__ import annotations

import subprocess
from pathlib import Path

from ..core import Task
from .base import BaseAdapter


class JustfileAdapter(BaseAdapter):
    marker = "justfile"

    def tasks(self, root: Path) -> list[Task]:
        try:
            result = subprocess.run(
                ["just", "--list", "--unsorted", "--list-prefix", ""],
                cwd=root,
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return []
        lines = result.stdout.splitlines()
        tasks = []
        for line in lines[1:]:  # skip header "Available recipes:"
            recipe = line.split()[0].rstrip(":")
            if recipe:
                tasks.append(Task(name=recipe, command=f"just {recipe}", provider="just", root=root))
        return tasks
