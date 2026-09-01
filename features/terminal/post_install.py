#!/usr/bin/env python3
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
        "import sys; print(sys.executable); print(sys.prefix != sys.base_prefix)",
    ],
    check=True,
    capture_output=True,
    text=True,
)
details = result.stdout.strip().splitlines()
if len(details) < 2:
    sys.exit("could not inspect the xonsh Python environment")
python, virtual_environment = details[-2:]
pip_options = ["--disable-pip-version-check"]
if virtual_environment != "True":
    pip_options[0:0] = ["--user", "--break-system-packages"]
subprocess.run(
    [python, "-m", "pip", "install", *pip_options, "xontrib-sh==0.3.2"],
    check=True,
)
