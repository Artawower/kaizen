#!/usr/bin/env python3

from pathlib import Path
import shutil
import subprocess
import sys

xonsh = shutil.which("xonsh")
if not xonsh:
    sys.exit("xonsh executable not found")


result = subprocess.run(
    [
        xonsh,
        "--no-rc",
        "-c",
        "import sys; print(sys.executable)",
    ],
    check=True,
    capture_output=True,
    text=True,
)

python = result.stdout.strip().splitlines()[-1]

xonsh_site = Path.home() / ".local" / "share" / "kaizen" / "xonsh-site"
xonsh_site.mkdir(parents=True, exist_ok=True)

subprocess.run(
    [
        python,
        "-m",
        "pip",
        "install",
        "--disable-pip-version-check",
        "--upgrade",
        "--target",
        str(xonsh_site),
        "xontrib-sh==0.3.2",
    ],
    check=True,
)


# Herdr installation

HERDR_PLUGINS = ["crierr/herdr-tmux-layout"]

for plugin in HERDR_PLUGINS:
    subprocess.run(
        ["herdr", "plugin", "install", plugin],
        check=True,
    )
