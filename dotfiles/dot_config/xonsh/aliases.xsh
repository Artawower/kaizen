import platform
import socket
from pathlib import Path

# Navigation
aliases['c']  = 'clear'
aliases['с']  = 'clear'
aliases['..'] = 'cd ../'
aliases['b']  = 'cd -'

# Editors
aliases['h']  = '/usr/bin/hx'
aliases['p']  = 'pi'
aliases['o']  = 'opencode'
aliases['e']  = 'emacsclient -ac ""'

# VCS
aliases['g']  = 'gitu'
aliases['п']  = 'gitu'   # cyrillic
aliases['ju'] = 'jjui'
aliases['jb'] = 'python3 ~/.config/scripts/jj-bisect.py'
aliases['ch'] = 'chezmoi'
aliases['czcd'] = 'cd $(chezmoi source-path)'

# Shell
aliases['y']  = 'yazi'
aliases['z']  = 'zellij'
aliases['l']  = '~/.config/scripts/layout'

# Python / pip
aliases['pip']    = 'pip3'
aliases['python'] = 'python3'

# File listing
aliases['ls']   = 'eza --icons'
aliases['tree'] = 'eza --tree'

# Bun
aliases['br']  = 'bun run'
aliases['bi']  = 'bun install'
aliases['bis'] = 'bun install --exact --save'
aliases['bid'] = 'bun install --exact --save --dev'

# Kubernetes / minikube
aliases['m']  = 'minikube'
aliases['ms'] = 'minikube start --driver=docker --alsologtostderr'
aliases['md'] = 'minikube dashboard'
aliases['kg'] = 'kubectl get'

# Docker
aliases['dc']  = 'docker compose'
aliases['dcu'] = 'docker compose up'
aliases['d']   = 'docker'


# Preserve PATH inside sudo (needed for Nix/mise commands)
aliases['sudo'] = 'sudo env PATH=$PATH'

# Just (uses ~/.config as justfile dir)
aliases['j'] = 'just ~/.config/'

if platform.system() == 'Darwin':
    aliases['yabai-apps']   = "yabai -m query --windows | jq '.[].app'"
    aliases['yabai-titles'] = "yabai -m query --windows | jq '.[].title'"

    _fqdn = socket.gethostname()
    _fqdn = _fqdn if '.' in _fqdn else f'{_fqdn}.local'
    _home = str(Path.home())
    aliases['displays']          = f'{_home}/.config/yabai/layouts/{_fqdn}/desktop.sh'
    aliases['preserve-displays'] = f'{_home}/.config/yabai/restore-script.sh'
    del _home, _fqdn


def _load_ssh_aliases() -> None:
    """Auto-generate `ssh <host>` aliases for every named Host in ~/.ssh/config."""
    ssh_config = Path.home() / '.ssh/config'
    if not ssh_config.exists():
        return
    for line in ssh_config.read_text().splitlines():
        line = line.strip()
        if not line.lower().startswith('host '):
            continue
        for host in line[5:].split():
            # skip wildcards, IPs, well-known service hosts
            if any(c in host for c in ('*', '?', '!')):
                continue
            if host.replace('.', '').isdigit():
                continue
            if host in ('github.com', 'gitlab.com', 'bitbucket.org'):
                continue
            aliases.setdefault(host, f'ssh {host}')

_load_ssh_aliases()
