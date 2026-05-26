from __future__ import annotations

from pathlib import Path

from xonsh.completers.tools import RichCompletion

from .adapters import CargoAdapter, JustfileAdapter, MakefileAdapter, NodeAdapter
from .cli import run_script
from .core import TaskCatalog

_CATALOG = TaskCatalog([
    JustfileAdapter(),
    NodeAdapter(),
    CargoAdapter(),
    MakefileAdapter(),
])

_COMMAND = "run-script"


def _make_completer(catalog: TaskCatalog):
    def _completer(prefix, line, begidx, endidx, ctx):
        words = line.split()
        if not words or words[0] != _COMMAND:
            return None
        tasks = catalog.collect(Path.cwd())
        completions = {
            RichCompletion(
                t.name,
                display=f"[{t.provider}] {t.name}",
                description=t.command,
                append_space=True,
            )
            for t in tasks
            if t.name.startswith(prefix)
        }
        return completions if completions else None
    return _completer


def _load_xontrib_(xsh, **kwargs):
    xsh.aliases[_COMMAND] = lambda args: run_script(args, _CATALOG)
    xsh.completers[_COMMAND] = _make_completer(_CATALOG)
    xsh.completers.move_to_end(_COMMAND, last=False)
