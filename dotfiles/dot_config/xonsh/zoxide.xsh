import shutil
from pathlib import Path

if shutil.which('zoxide'):
    execx($(zoxide init xonsh --hook none), 'exec', __xonsh__.ctx, filename='zoxide')

    @builtins.events.on_chdir  # type: ignore
    def __zoxide_vcs_hook(newdir, olddir, **_kwargs):
        p = Path(newdir)
        if any((p / marker).exists() for marker in ('.git', '.jj')):
            subprocess.run(
                [__zoxide_bin(), 'add', '--', newdir],
                check=False,
                env=__zoxide_env(),
            )
