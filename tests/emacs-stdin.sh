#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$project_dir" <<'PY'
import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import termios
import time

project = Path(sys.argv[1])
wrapper = project / 'dotfiles/dot_config/bin/executable_emacs-terminal'

with tempfile.TemporaryDirectory(prefix='kaizen-emacs-stdin-') as folder:
    root = Path(folder)
    binary = root / 'bin'
    binary.mkdir()
    temporary = root / 'temporary files'
    temporary.mkdir()
    record = root / 'client.json'
    (binary / 'emacs-terminal').symlink_to(wrapper)
    client = binary / 'emacsclient'
    client.write_text('''#!/usr/bin/env python3
import base64
import json
import os
from pathlib import Path
import sys

path = Path(sys.argv[-1]) if len(sys.argv) > 1 else None
payload = path.read_bytes() if path and path.name.startswith('emacs-stdin.') else None
Path(os.environ['KAIZEN_CLIENT_RECORD']).write_text(json.dumps({
    'arguments': sys.argv[1:],
    'terminal': sys.stdin.isatty(),
    'payload': base64.b64encode(payload).decode() if payload is not None else None,
}))
sys.exit(int(os.environ.get('KAIZEN_CLIENT_EXIT', '0')))
''')
    client.chmod(0o755)
    env = {**os.environ, 'HOME': str(root), 'PATH': f'{binary}:{os.environ["PATH"]}',
           'TMPDIR': str(temporary), 'KAIZEN_CLIENT_RECORD': str(record),
           'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_CACHE_HOME': str(root / 'cache'),
           'XDG_DATA_HOME': str(root / 'data'), 'TERM': 'xterm-256color'}

    def attach_terminal():
        os.setsid()
        fcntl.ioctl(1, termios.TIOCSCTTY, 0)

    def run(command, payload=None, status=0, expected=0):
        record.unlink(missing_ok=True)
        master, slave = pty.openpty()
        process = subprocess.Popen(command, env={**env, 'KAIZEN_CLIENT_EXIT': str(status)},
                                   stdin=subprocess.PIPE if payload is not None else slave,
                                   stdout=slave, stderr=slave, preexec_fn=attach_terminal)
        os.close(slave)
        output = bytearray()
        try:
            if payload is not None:
                process.stdin.write(payload)
                process.stdin.close()
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
            assert process.wait(timeout=2) == expected, output.decode(errors='replace')
            assert not list(temporary.glob('emacs-stdin.*')), 'temporary input leaked'
            return json.loads(record.read_text()) if record.exists() else None
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            os.close(master)

    arguments = ['file with spaces', '+12:3', 'another-file']
    result = run([str(wrapper), *arguments])
    assert result['arguments'] == ['-nw', *arguments] and result['terminal'], result
    assert result['payload'] is None, result
    print('passed: ordinary file arguments and terminal input', flush=True)

    payload = 'command help: "quoted" \\ slash\nUnicode: λ\n'.encode() + b'\x00'
    for data in [payload, b'']:
        result = run([str(wrapper), '--socket-name=fixture'], data)
        assert result['arguments'][:2] == ['-nw', '--socket-name=fixture'], result
        assert result['terminal'] and base64.b64decode(result['payload']) == data, result
    print('passed: piped bytes, empty input, paths with spaces and cleanup', flush=True)

    run([str(wrapper)], b'help', status=17, expected=17)
    print('passed: client failure status and cleanup', flush=True)

    xonsh = shutil.which('xonsh')
    if xonsh:
        aliases = shlex.quote(str(project / 'dotfiles/dot_config/xonsh/aliases.xsh'))
        result = run([xonsh, '--no-rc', '-c',
                      f"source {aliases}; printf '%s' 'xonsh pipeline help' | em --socket-name=fixture"])
        assert result['terminal'] and base64.b64decode(result['payload']) == b'xonsh pipeline help', result
        print('passed: real xonsh alias and pipeline', flush=True)
    else:
        print('skipped: xonsh is not installed', flush=True)
PY
