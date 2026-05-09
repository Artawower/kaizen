from pathlib import Path
from xonsh import color_tools
import platform
import re
import subprocess


def _hx(args):
    """Helix with auto theme-switching based on system appearance."""
    system = platform.system()
    is_dark = True
    try:
        if system == 'Darwin':
            r = subprocess.run(
                ['osascript', '-e',
                 'tell application "System Events" to tell appearance preferences to get dark mode'],
                capture_output=True, text=True, timeout=1,
            )
            is_dark = r.stdout.strip() == 'true'
        elif system == 'Linux':
            r = subprocess.run(
                ['gsettings', 'get', 'org.gnome.desktop.interface', 'color-scheme'],
                capture_output=True, text=True, timeout=1,
            )
            is_dark = 'dark' in r.stdout.lower()
    except Exception:
        pass

    theme = 'my' if is_dark else 'my_light'
    config = Path.home() / '.config/helix/config.toml'
    if config.exists():
        content = config.read_text()
        updated = re.sub(r'^theme = .*', f'theme = "{theme}"', content, flags=re.MULTILINE)
        if updated != content:
            config.write_text(updated)
    ![hx @(args)]


def _vis(args):
    """Install a global npm package via mise: vis <package>"""
    ![mise use --global npm:@(args)]


def _docker_clean(args):
    """Remove all unused Docker images, containers, networks, and volumes."""
    ![docker image prune -a]
    ![docker system prune -a --volumes]


def _clean_space(args):
    """Free disk space: Docker cleanup + Nix garbage collection."""
    _docker_clean(args)
    ![nix-collect-garbage]


def pnpm_update_all():
    """Update all global pnpm packages."""
    res = $(pnpm list -g --depth=0 --parseable).strip().split('\n')
    packages = []
    for line in res:
        name = (line.split('/')[-1] if '/' in line
                else line.split('node_modules/')[-1] if 'node_modules/' in line
                else '')
        if name and name not in ('pnpm', 'npm') and not name.startswith('.'):
            packages.append(name)
    if packages:
        pnpm add -g @(packages)
    else:
        print('No global packages to update')


def _ghll(args):
    """Show logs for the latest GitHub Actions run."""
    run_id = $(gh run list --limit 1 --json databaseId --jq '.[0].databaseId').strip()
    ![gh run view @(run_id) --log | cat @(args)]


def _reload(args):
    """Reload xonsh config."""
    config_path = Path.home() / '.config/xonsh/rc.xsh'
    if config_path.exists():
        execx(open(config_path).read(), 'exec', __xonsh__.ctx, filename=str(config_path))
        print('Config reloaded')
    else:
        print(f'Config not found: {config_path}')


def print_colors():
    """Print all xonsh base colors with their RGB values."""
    for name, (r, g, b) in color_tools.BASE_XONSH_COLORS.items():
        row = "\033[48;2;{};{};{}m  \033[0m {:20} rgb({},{},{})".format(r, g, b, name, r, g, b)
        print(row)


aliases['hx']           = _hx
aliases['vis']          = _vis
aliases['docker-clean'] = _docker_clean
aliases['clean-space']  = _clean_space
aliases['ghll']         = _ghll
aliases['reload']       = _reload
aliases['r']            = _reload
