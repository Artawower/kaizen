import shutil
from xonsh.tools import unthreadable, uncapturable


# unthreadable + uncapturable: interactive fzf (spawned by `zoxide query -i`)
# needs the controlling tty. A threadable/captured callable alias hides the tty,
# so fzf returns nothing and the alias silently does nothing.
@unthreadable
@uncapturable
def _kaizen_zoxide_pick(args):
    zoxide = shutil.which('zoxide')
    if not zoxide:
        return
    dest = $(@(zoxide) query -i -- @(args)).strip()
    if dest:
        cd @(dest)


aliases['vl'] = 'jjui'
# projects.pick → zoxide interactive directly (no dependency on zoxide's own `zi`
# alias, which only exists after `zoxide init` runs and was order/PATH-fragile).
aliases[''.join(["p","p"])] = _kaizen_zoxide_pick
