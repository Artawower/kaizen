#!/usr/bin/env python3
# @vicinae.schemaVersion 1
# @vicinae.title Reload xremap
# @vicinae.mode fullOutput

import os
import subprocess

try:
    for process_name in ("xremap", "xremap-wlroots"):
        subprocess.run(["pkill", "-x", process_name], check=False)
except Exception:
    print("Error killing xremap")

try:
    config_path = os.path.expanduser("~/.config/xremap/config.yml")
    xremap_bin = "/usr/bin/xremap"
    if not os.path.isfile(xremap_bin) or not os.access(xremap_bin, os.X_OK):
        xremap_bin = os.path.expanduser("~/.local/bin/xremap-wlroots")
    subprocess.Popen(
        [xremap_bin, "--device", "Apple SPI Keyboard", "--watch=config,device", config_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    subprocess.run(["notify-send", "-t", "500", "-u", "low", "Xremap restarted"])
    subprocess.run(["vicinae", "close"])
except Exception:
    subprocess.run(["notify-send", "-t", "500", "-u", "low", "Failed to restart"])


