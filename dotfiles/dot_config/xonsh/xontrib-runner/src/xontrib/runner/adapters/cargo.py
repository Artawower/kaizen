from __future__ import annotations

from pathlib import Path

from ..core import Task
from .base import BaseAdapter

_CARGO_COMMANDS = [
    "build", "run", "test", "check", "clean",
    "doc", "clippy", "fmt", "bench", "fetch",
]


class CargoAdapter(BaseAdapter):
    marker = "Cargo.toml"

    def tasks(self, root: Path) -> list[Task]:
        return [
            Task(name=cmd, command=f"cargo {cmd}", provider="cargo", root=root)
            for cmd in _CARGO_COMMANDS
        ]
