#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)

python3 - "$PROJECT_DIR" <<'PY'
import os
import shlex
import shutil
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace


class Environment(dict):
    def detype(self):
        return dict(self)


class Event(set):
    def __call__(self, handler):
        self.add(handler)


root = Path(sys.argv[1])
source = root / "dotfiles/dot_config/xonsh"
if not source.exists():
    source = root / ".arhive/xonsh/dotfiles/dot_config/xonsh"
activation = """for event in (__xonsh__.builtins.events.on_pre_prompt, __xonsh__.builtins.events.on_chdir):
    for handler in list(event):
        if handler.__name__ == 'mise_hook':
            event.remove(handler)
"""

with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary)
    binary_dir = home / "bin"
    binary_dir.mkdir()
    environment = Environment(os.environ, HOME=str(home), PATH=str(binary_dir))
    events = SimpleNamespace(on_pre_prompt=Event(), on_chdir=Event())
    namespace = {}
    namespace["__xonsh__"] = SimpleNamespace(
        env=environment,
        builtins=SimpleNamespace(events=events),
        ctx=namespace,
    )

    def execx(code, mode, context, filename):
        exec(compile(code, filename, mode), context)

    namespace["execx"] = execx
    exec(compile((source / "cache.xsh").read_text(), "cache.xsh", "exec"), namespace)
    namespace["CACHE_DIR"] = home / "cache"

    def install(version):
        directory = home / version
        directory.mkdir()
        binary = directory / "mise"
        hook = f"__xonsh__.env['MISE_TEST_VERSION'] = {version!r}"
        binary.write_text(
            "#!/bin/sh\n"
            'case "$1" in\n'
            'activate)\n'
            '  [ "$*" = "activate xonsh --no-hook-env" ] || exit 2\n'
            f"  printf '%s\\n' {shlex.quote(activation)}\n"
            '  ;;\n'
            'hook-env)\n'
            '  [ "$*" = "hook-env -s xonsh" ] || exit 2\n'
            f"  printf '%s\\n' {shlex.quote(hook)}\n"
            '  ;;\n'
            '*) exit 2 ;;\n'
            'esac\n'
        )
        binary.chmod(0o755)
        link = binary_dir / "mise"
        link.unlink(missing_ok=True)
        link.symlink_to(binary)
        return directory

    def load():
        os.environ["PATH"] = environment["PATH"]
        exec(compile((source / "mise.xsh").read_text(), "mise.xsh", "exec"), namespace)

    old_installation = install("old")
    load()
    assert environment["MISE_TEST_VERSION"] == "old"
    load()
    assert len(events.on_pre_prompt) == len(events.on_chdir) == 1

    install("new")
    shutil.rmtree(old_installation)
    for event in (events.on_pre_prompt, events.on_chdir):
        environment["MISE_TEST_VERSION"] = "stale"
        for handler in event:
            handler()
        assert environment["MISE_TEST_VERSION"] == "new"

    load()
    assert len(events.on_pre_prompt) == len(events.on_chdir) == 1
    assert len(list((home / "cache").glob("mise-activate-*.xsh"))) == 1

    (binary_dir / "mise").unlink()
    for handler in events.on_pre_prompt:
        handler()
    events.on_pre_prompt.clear()
    events.on_chdir.clear()
    load()
    assert not events.on_pre_prompt and not events.on_chdir

print("xonsh mise hook tests passed")
PY
