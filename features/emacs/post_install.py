#!/usr/bin/env python3
"""Post-install for emacs feature: copy Emacs.app to /Applications."""

import subprocess
import sys
from pathlib import Path

os_name = sys.argv[1] if len(sys.argv) > 1 else ""

if os_name != "macos":
    sys.exit(0)

emacs_src = Path("/opt/homebrew/opt/emacs-plus@31/Emacs.app")
emacs_dst = Path("/Applications/Emacs.app")

if not emacs_src.exists():
    print("  emacs-plus not found, skipping .app copy")
    sys.exit(0)

src_bin = emacs_src / "Contents/MacOS/Emacs"
dst_bin = emacs_dst / "Contents/MacOS/Emacs"

if emacs_dst.exists() and dst_bin.stat().st_mtime >= src_bin.stat().st_mtime:
    print("  Emacs.app already up to date")
    sys.exit(0)

subprocess.run(["rm", "-rf", str(emacs_dst)], check=True)
subprocess.run(["cp", "-r", str(emacs_src), str(emacs_dst)], check=True)
print(f"  Emacs.app copied to {emacs_dst}")
