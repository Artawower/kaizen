from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from .core import Task, TaskCatalog


def _fzf(tasks: list[Task]) -> Task | None:
    items = "\n".join(t.display for t in tasks)
    try:
        result = subprocess.run(
            ["fzf", "--prompt", "run> ", "--ansi"],
            input=items,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        print("fzf not found — install fzf or pass a task name directly", file=sys.stderr)
        return None
    if result.returncode != 0:
        return None
    selected = result.stdout.strip()
    return next((t for t in tasks if t.display == selected), None)


def run_script(args: list[str], catalog: TaskCatalog) -> None:
    tasks = catalog.collect(Path.cwd())
    if not tasks:
        print("No tasks found (checked: justfile, package.json, Makefile, Cargo.toml)")
        return

    if args:
        query = " ".join(args)
        matches = [t for t in tasks if t.name == query or t.display == query]
        task = matches[0] if matches else None
        if task is None:
            print(f"No task named {query!r}. Available: {[t.name for t in tasks]}")
            return
    else:
        task = _fzf(tasks)

    if task is None:
        return

    subprocess.run(task.command, shell=True, cwd=task.root)


def complete_tasks(prefix: str, catalog: TaskCatalog) -> set[str]:
    tasks = catalog.collect(Path.cwd())
    return {t.name for t in tasks if t.name.startswith(prefix)}
