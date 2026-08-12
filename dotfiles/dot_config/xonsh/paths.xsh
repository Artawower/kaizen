from pathlib import Path
import platform

home = Path.home()
IS_DARWIN = platform.system() == 'Darwin'
IS_LINUX  = platform.system() == 'Linux'

for _p in [
    home / 'bin',
    home / '.local/bin',
    home / '.config/bin',
    home / '.config/scripts',
    home / '.local/share/mise/shims',
    home / '.local/share/uv/tools',
    home / '.cargo/bin',
    home / 'go/bin',
    home / '.go/bin',
]:
    $PATH.insert(0, str(_p))

if IS_DARWIN:
    for _p in ['/opt/homebrew/sbin', '/opt/homebrew/bin', '/opt/homebrew/opt/libpq/bin']:
        $PATH.insert(0, _p)

    $PATH.insert(0, str(home / '.orbstack/bin'))

    _sdk = home / 'Library/Android/sdk'
    $ANDROID_SDK_ROOT = str(_sdk)
    $ANDROID_HOME     = str(_sdk)
    $PATH.insert(0, str(_sdk / 'cmdline-tools/latest/bin'))
    $PATH.insert(0, str(_sdk / 'platform-tools'))
    del _sdk

if IS_LINUX:
    for _p in ['/usr/sbin', '/usr/bin', '/usr/local/bin']:
        $PATH.insert(0, _p)

del _p, home, IS_DARWIN, IS_LINUX, platform, Path
