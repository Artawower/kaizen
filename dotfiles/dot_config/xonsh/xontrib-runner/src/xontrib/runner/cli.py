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
        name, extra = args[0], args[1:]
        matches = [t for t in tasks if t.name == name or t.display == name]
        task = matches[0] if matches else None
        if task is None:
            print(f"No task named {name!r}. Available: {[t.name for t in tasks]}")
            return
    else:
        task = _fzf(tasks)
        extra = []

    if task is None:
        return

    command = task.command
    if extra:
        command = f"{command} {' '.join(extra)}"
    subprocess.run(command, shell=True, cwd=task.root)


def complete_tasks(prefix: str, catalog: TaskCatalog) -> set[str]:
    tasks = catalog.collect(Path.cwd())
    return {t.name for t in tasks if t.name.startswith(prefix)}
