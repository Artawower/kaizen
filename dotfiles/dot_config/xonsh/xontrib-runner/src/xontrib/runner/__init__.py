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

# "rt" is derived from run.task keys ["r","t"] in dotfiles/kaizen/keybindings.toml.
# If the shortcut keys change, update this set accordingly.
_COMMANDS = {"run-script", "rt"}


def _make_completer(catalog: TaskCatalog):
    def _completer(prefix, line, begidx, endidx, ctx):
        words = line.split()
        if not words or words[0] not in _COMMANDS:
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
    handler = lambda args: run_script(args, _CATALOG)
    completer = _make_completer(_CATALOG)
    for cmd in _COMMANDS:
        xsh.aliases[cmd] = handler
        xsh.completers[cmd] = completer
        xsh.completers.move_to_end(cmd, last=False)
