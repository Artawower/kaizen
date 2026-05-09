import shutil
from pathlib import Path

if shutil.which('zoxide'):
    # --hook none: suppress default hook; we register our own below
    execx($(zoxide init xonsh --hook none), 'exec', __xonsh__.ctx, filename='zoxide')
    aliases['pp'] = aliases['zi']  # interactive zoxide picker (fzf)

    @builtins.events.on_chdir  # type: ignore
    def __zoxide_vcs_hook(newdir, olddir, **_kwargs):
        """Add to zoxide only when the directory is a VCS root (.git or .jj)."""
        p = Path(newdir)
        if any((p / marker).exists() for marker in ('.git', '.jj')):
            subprocess.run(
                [__zoxide_bin(), 'add', '--', newdir],
                check=False,
                env=__zoxide_env(),
            )
