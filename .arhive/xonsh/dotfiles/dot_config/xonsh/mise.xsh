import shutil
import subprocess


def mise_hook(**kwargs):
    environment = __xonsh__.env.detype()
    binary = shutil.which('mise', path=environment.get('PATH'))
    if binary is None:
        return
    script = subprocess.run(
        [binary, 'hook-env', '-s', 'xonsh'],
        env=environment,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    execx(script, 'exec', __xonsh__.ctx, filename='mise-hook')


_mise_activation = cached_init('mise-activate', ['mise', 'activate', 'xonsh', '--no-hook-env'])
if _mise_activation is not None:
    execx(_mise_activation, 'exec', __xonsh__.ctx, filename='mise')
    __xonsh__.builtins.events.on_pre_prompt(mise_hook)
    __xonsh__.builtins.events.on_chdir(mise_hook)
    mise_hook()
del _mise_activation
