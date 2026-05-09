"""Keybindings entry point — loads layout-specific + shared modules.

Layout is read from chezmoi data (default: qwerty).
Uses exec() instead of source() to work in all xonsh contexts.
"""
import os


def _detect_layout():
    """Read layout from chezmoi data, default to qwerty."""
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError:
            return "qwerty"

    paths = [
        os.path.expanduser("~/.local/share/chezmoi/.chezmoidata.toml"),
        os.path.expanduser("~/.config/chezmoi/chezmoi.toml"),
    ]
    for path in paths:
        if os.path.exists(path):
            try:
                with open(path, "rb") as f:
                    data = tomllib.load(f)
                return data.get("layout", data.get("data", {}).get("layout", "qwerty"))
            except Exception:
                continue
    return "qwerty"


def _load_module(filename):
    """Load a .xsh module by exec-ing it in the current namespace."""
    xonsh_dir = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.path.expanduser("~/.config/xonsh")
    filepath = os.path.join(xonsh_dir, filename)
    with open(filepath) as f:
        code = compile(f.read(), filepath, "exec")
    return code


layout = _detect_layout()

if layout == "colemak":
    exec(_load_module("keybindings_colemak.xsh"))
else:
    exec(_load_module("keybindings_qwerty.xsh"))

exec(_load_module("keybindings_shared.xsh"))
