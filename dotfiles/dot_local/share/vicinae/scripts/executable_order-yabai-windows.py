#!/usr/bin/env python3
# @vicinae.schemaVersion 1
# @vicinae.title Order Windows
# @vicinae.icon 🪟
# @vicinae.mode compact
# @vicinae.description Move yabai windows to their configured spaces
# @vicinae.keywords ["yabai", "windows", "spaces", "macos"]

import os
import platform
import subprocess
import sys
from pathlib import Path


SCRIPT_PATH = Path.home() / ".config/yabai/order_windows.py"


def build_environment() -> dict[str, str]:
    env = os.environ.copy()

    # GUI applications on macOS often receive a limited PATH.
    extra_paths = [
        str(Path.home() / ".nix-profile/bin"),
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    current_path = env.get("PATH", "")
    env["PATH"] = os.pathsep.join(
        path for path in [*extra_paths, current_path] if path
    )

    return env


def main() -> int:
    if platform.system() != "Darwin":
        print("Order Windows is available only on macOS")
        return 1

    if not SCRIPT_PATH.is_file():
        print(f"Script not found: {SCRIPT_PATH}")
        return 1

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        text=True,
        capture_output=True,
        env=build_environment(),
    )

    if result.returncode != 0:
        output = result.stderr.strip() or result.stdout.strip()
        last_line = output.splitlines()[-1] if output else "unknown error"
        print(f"Failed to order windows: {last_line}")
        return result.returncode

    moved_windows = sum(
        line.startswith("Moving window")
        for line in result.stdout.splitlines()
    )

    if moved_windows:
        print(f"Windows ordered: {moved_windows} moved")
    else:
        print("Windows ordered: nothing to move")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
