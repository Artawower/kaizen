import os


def _load_module(filename):
    xonsh_dir = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.path.expanduser("~/.config/xonsh")
    filepath = os.path.join(xonsh_dir, filename)
    with open(filepath) as file:
        return compile(file.read(), filepath, "exec")


exec(_load_module("keybindings_qwerty.xsh"))
exec(_load_module("keybindings_shared.xsh"))
