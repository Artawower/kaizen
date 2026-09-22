#!/usr/bin/env python3
# @vicinae.schemaVersion 1
# @vicinae.title Toggle Dark Mode
# @vicinae.mode silent

import subprocess
from pathlib import Path

SYNC_APPEARANCE = Path.home() / ".config/noctalia/scripts/sync-system-appearance"


def notify(title: str, body: str = "") -> None:
    subprocess.run(
        ["notify-send", "-t", "1200", "-u", "low", title, body],
        check=False,
    )


def main() -> int:
    result = subprocess.run(
        ["noctalia", "msg", "theme-mode-toggle"],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        notify("Failed to toggle dark mode", result.stderr.strip())
        return 1

    mode = subprocess.run(
        ["noctalia", "msg", "theme-mode-get"],
        check=False,
        text=True,
        capture_output=True,
    ).stdout.strip().lower()
    if mode not in {"dark", "light"}:
        notify("Failed to read theme mode")
        return 1
    subprocess.run([str(SYNC_APPEARANCE), mode], check=False)
    notify("Dark mode" if mode == "dark" else "Light mode")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
