import os.path as op
import platform
import subprocess as _subprocess

_secrets = op.expanduser('~/.config/xonsh/.secrets.xsh')
if op.exists(_secrets):
    source @(_secrets)
del _secrets, op

$EDITOR   = 'hx'
$VISUAL   = 'hx'
$JJ_EDITOR = 'hx'

$VI_MODE = 'INSIDE_EMACS' not in ${...}
$AUTO_CD  = True

$XONSH_COLOR_STYLE     = 'one-dark'
$XONSH_HISTORY_BACKEND = 'sqlite'

$XONSH_STYLE_OVERRIDES = {
    'Token.Name':          'ansired',
    'Token.Name.Builtin':  'ansibrightcyan',
    'Token.Name.Constant': 'ansibrightblue',
    'Token.Literal.String':'ansibrightgreen',
}

$TITLE = '{current_job:{} | }{cwd}'

_tty = _subprocess.run(['tty'], capture_output=True, text=True)
if _tty.returncode == 0 and _tty.stdout.strip():
    $GPG_TTY = _tty.stdout.strip()
del _tty

$LSP_USE_PLISTS          = 'true'   # Emacs lsp-mode: faster plist-based deserialization
$DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$DOTNET_ROLL_FORWARD     = 'Major'

if platform.system() == 'Darwin':
    $DOTNET_ROOT = '/usr/local/share/dotnet'
    $TMPDIR = '/tmp'

if platform.system() == 'Linux':
    $FREETYPE_PROPERTIES = 'cff:no-stem-darkening=0 autofitter:no-stem-darkening=0'

del _subprocess, platform
