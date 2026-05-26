from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Task:
    name: str
    command: str
    provider: str
    root: Path

    @property
    def display(self) -> str:
        return f"[{self.provider}] {self.name}"


class TaskCatalog:
    """Aggregates tasks from all registered adapters. No I/O beyond file reads."""

    def __init__(self, adapters: list) -> None:
        self._adapters = adapters

    def collect(self, cwd: Path) -> list[Task]:
        tasks: list[Task] = []
        seen: set[str] = set()
        for adapter in self._adapters:
            root = adapter.find_root(cwd)
            if root is None:
                continue
            for task in adapter.tasks(root):
                if task.display not in seen:
                    tasks.append(task)
                    seen.add(task.display)
        return tasks
