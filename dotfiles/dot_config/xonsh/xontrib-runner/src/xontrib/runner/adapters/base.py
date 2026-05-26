from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from ..core import Task


class BaseAdapter(ABC):
    marker: str

    def find_root(self, cwd: Path) -> Path | None:
        current = cwd.resolve()
        while True:
            if (current / self.marker).exists():
                return current
            parent = current.parent
            if parent == current:
                return None
            current = parent

    @abstractmethod
    def tasks(self, root: Path) -> list[Task]:
        ...
