# Monkey patch xonsh.tools.decode to handle strings
import xonsh.tools

def fixed_decode(s, encoding=None):
    encoding = encoding or xonsh.tools.DEFAULT_ENCODING
    if isinstance(s, bytes):
        return s.decode(encoding, "replace")
    elif isinstance(s, str):
        return s
    else:
        raise TypeError(f"Expected bytes or str, got {type(s)}")

xonsh.tools.decode = fixed_decode

import platform
import shutil
import subprocess
import sys
from pathlib import Path
from pprint import pprint

config_dir = Path.home() / '.config/xonsh'
xonsh_site = Path.home() / '.local/share/kaizen/xonsh-site'
if xonsh_site.is_dir() and str(xonsh_site) not in sys.path:
    sys.path.insert(0, str(xonsh_site))

try:
    import xontrib.sh
    $XONTRIB_SH_SHELLS = ['bash', 'sh']
    xontrib load sh
except Exception as _sh_error:
    print(f"warning: failed to load xontrib-sh: {_sh_error}")


source @(config_dir / 'env.xsh')
source @(config_dir / 'paths.xsh')
source @(config_dir / 'cache.xsh')
source @(config_dir / 'mise.xsh')
source @(config_dir / 'keybindings.xsh')
source @(config_dir / 'hooks.xsh')
source @(config_dir / 'functions.xsh')
if platform.system() == 'Darwin':
    source @(config_dir / 'functions_darwin.xsh')
elif platform.system() == 'Linux':
    source @(config_dir / 'functions_linux.xsh')
source @(config_dir / 'aliases.xsh')
source @(config_dir / 'completers.xsh')
source @(config_dir / 'filters.xsh')
source @(config_dir / 'prompt.xsh')
source @(config_dir / 'zoxide.xsh')
source @(config_dir / 'task-runner.xsh')
source @(config_dir / 'generated.xsh')
source @(config_dir / 'autoenv.xsh')
source @(config_dir / 'smartenv.xsh')


# Fedora system binaries (e.g. libz version mismatch in binutils).
if platform.system() == 'Linux':
    if 'LD_LIBRARY_PATH' in ${...}:
        del $LD_LIBRARY_PATH
    $__EGL_VENDOR_LIBRARY_FILENAMES = '/usr/share/glvnd/egl_vendor.d/50_mesa.json'
    $__GLX_VENDOR_LIBRARY_NAME = 'mesa'
    $LIBGL_DRIVERS_PATH = '/usr/lib64/dri'
    $GBM_BACKENDS_PATH = '/usr/lib64/gbm'
    $VDPAU_DRIVER_PATH = '/usr/lib64/vdpau'
    $VK_ICD_FILENAMES = '/usr/share/vulkan/icd.d/asahi_icd.aarch64.json'
    $VK_LAYER_PATH = '/usr/share/vulkan/explicit_layer.d:/usr/share/vulkan/implicit_layer.d'
    $XDG_DATA_DIRS = [p for p in $XDG_DATA_DIRS if p and not p.startswith('/opt/homebrew/') and '/Library/' not in p]
    for _share_dir in ['/usr/local/share', '/usr/share', str(Path.home() / '.local/share/flatpak/exports/share'), '/var/lib/flatpak/exports/share']:
        if _share_dir not in $XDG_DATA_DIRS:
            $XDG_DATA_DIRS.append(_share_dir)
    if 'QT_PLUGIN_PATH' in ${...}:
        del $QT_PLUGIN_PATH
    del _share_dir
