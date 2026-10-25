#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path

if len(sys.argv) > 1 and sys.argv[1] == "macos":
    screenshots = Path.home() / "Pictures" / "screenshots"
    screenshots.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["/usr/bin/defaults", "write", "com.apple.screencapture", "location", "-string", str(screenshots)],
        check=True,
    )
    subprocess.run(["/usr/bin/killall", "Dock"], check=False)
