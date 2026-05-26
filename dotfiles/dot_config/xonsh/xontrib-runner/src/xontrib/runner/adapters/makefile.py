from __future__ import annotations

import re
from pathlib import Path

from ..core import Task
from .base import BaseAdapter

_TARGET_RE = re.compile(r"^([a-zA-Z0-9_][a-zA-Z0-9_\-]*):")


class MakefileAdapter(BaseAdapter):
    marker = "Makefile"

    def tasks(self, root: Path) -> list[Task]:
        try:
            text = (root / "Makefile").read_text()
        except OSError:
            return []
        targets = []
        for line in text.splitlines():
            m = _TARGET_RE.match(line)
            if m:
                name = m.group(1)
                targets.append(Task(name=name, command=f"make {name}", provider="make", root=root))
        return targets
