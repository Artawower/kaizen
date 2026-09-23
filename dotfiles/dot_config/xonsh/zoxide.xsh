from pathlib import Path

_zoxide_init = cached_init('zoxide-init', ['zoxide', 'init', 'xonsh', '--hook', 'none'])
if _zoxide_init is not None:
    execx(_zoxide_init, 'exec', __xonsh__.ctx, filename='zoxide')

    @builtins.events.on_chdir  # type: ignore
    def __zoxide_vcs_hook(newdir, olddir, **_kwargs):
        p = Path(newdir)
        if any((p / marker).exists() for marker in ('.git', '.jj')):
            subprocess.run(
                [__zoxide_bin(), 'add', '--', newdir],
                check=False,
                env=__zoxide_env(),
            )

    del _zoxide_init
