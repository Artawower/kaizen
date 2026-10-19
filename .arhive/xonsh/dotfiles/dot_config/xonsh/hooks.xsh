import shutil
import subprocess

_WAKATIME = shutil.which('wakatime')


def _wakatime_hook(cmd, rtn, out, ts):
    if not _WAKATIME:
        return
    try:
        command = cmd if isinstance(cmd, str) else ' '.join(cmd) if cmd else 'terminal'
        subprocess.Popen(
            [_WAKATIME, '--plugin', 'xonsh-wakatime/1.0.0',
             '--write', '--entity-type', 'domain',
             '--entity', 'terminal', '--project', command,
             '--language', 'shell'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


if hasattr(__xonsh__.builtins, 'events'):
    __xonsh__.builtins.events.on_postcommand(_wakatime_hook)
