#!/usr/bin/env python3
# @vicinae.schemaVersion 1
# @vicinae.title Lock
# @vicinae.mode silent

import subprocess

result = subprocess.run(["noctalia", "msg", "session", "lock"], check=False)
if result.returncode != 0:
    subprocess.run(
        ["notify-send", "-t", "800", "-u", "low", "Failed to lock screen"],
        check=False,
    )
