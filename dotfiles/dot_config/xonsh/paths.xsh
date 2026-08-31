from pathlib import Path
import platform

home = Path.home()
IS_DARWIN = platform.system() == 'Darwin'
IS_LINUX  = platform.system() == 'Linux'

_paths = [
    home / 'bin',
    home / '.local/bin',
    home / '.config/bin',
    home / '.config/scripts',
    home / '.local/share/mise/shims',
    home / '.local/share/uv/tools',
    home / '.cargo/bin',
    home / 'go/bin',
    home / '.go/bin',
    home / '.steel/bin',
    home / '.local/share/steel/bin',
]

if IS_DARWIN:
    _paths.extend(['/opt/homebrew/sbin', '/opt/homebrew/bin', '/opt/homebrew/opt/libpq/bin'])
    _paths.append(home / '.orbstack/bin')

    _sdk = home / 'Library/Android/sdk'
    $ANDROID_SDK_ROOT = str(_sdk)
    $ANDROID_HOME     = str(_sdk)
    _paths.extend([_sdk / 'cmdline-tools/latest/bin', _sdk / 'platform-tools'])
    del _sdk

if IS_LINUX:
    _paths.extend(['/usr/sbin', '/usr/bin', '/usr/local/bin'])

for _p in reversed(_paths):
    _path = str(_p)
    if _path in $PATH:
        $PATH.remove(_path)
    $PATH.insert(0, _path)

del _p, _path, _paths, home, IS_DARWIN, IS_LINUX, platform, Path
