#!/usr/bin/env python3
import shutil
import subprocess
import sys

xonsh = shutil.which("xonsh")
if not xonsh:
    sys.exit("xonsh executable not found")

result = subprocess.run(
    [xonsh, "--no-rc", "-c", "import sys; print(sys.executable)"],
    check=True,
    capture_output=True,
    text=True,
)
python = result.stdout.strip().splitlines()[-1]
subprocess.run(
    [
        python,
        "-m",
        "pip",
        "install",
        "--user",
        "--break-system-packages",
        "--disable-pip-version-check",
        "xontrib-sh==0.3.2",
    ],
    check=True,
)
