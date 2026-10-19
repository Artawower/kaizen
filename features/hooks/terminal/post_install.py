#!/usr/bin/env python3

import shutil
import subprocess

HERDR_PLUGINS = ["crierr/herdr-tmux-layout"]

herdr = shutil.which("herdr")
if herdr:
    for plugin in HERDR_PLUGINS:
        subprocess.run(
            [herdr, "plugin", "install", plugin, "-y"],
            check=True,
        )
