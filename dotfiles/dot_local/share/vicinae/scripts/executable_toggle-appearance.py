#!/usr/bin/env python3
# @vicinae.schemaVersion 1
# @vicinae.title Toggle Appearance
# @vicinae.icon 🌓
# @vicinae.mode compact
# @vicinae.subtitle Toggle system light/dark appearance
"""Toggle the system appearance between light and dark.

Vicinae follows the system appearance and automatically switches between the
themes configured under `theme.light` and `theme.dark` in settings.json, so
toggling the system appearance is all that's needed to toggle Vicinae's look.

- macOS: uses System Events (Ventura+) with a `defaults` fallback.
- Linux: uses `gsettings` (org.gnome.desktop.interface color-scheme) and, when
  present, reuses the noctalia sync hook so the niri/desktop setup stays in sync.
"""

import platform
import subprocess
from pathlib import Path


def run(cmd: list[str], *, check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


# --- macOS -----------------------------------------------------------------

def macos_current() -> str:
    res = run(["defaults", "read", "-g", "AppleInterfaceStyle"])
    return "dark" if res.stdout.strip() == "Dark" else "light"


def macos_set(mode: str) -> None:
    # System Events "appearance preferences" works on macOS Ventura+.
    if mode == "dark":
        enable = "true"
    else:
        enable = "false"
    script = (
        'tell application "System Events" to set dark mode '
        "of appearance preferences to " + enable
    )
    res = run(["osascript", "-e", script])
    if res.returncode != 0:
        # Fallback for older macOS: write AppleInterfaceStyle and refresh prefs.
        if mode == "dark":
            run(["defaults", "write", "-g", "AppleInterfaceStyle", "-string", "Dark"])
        else:
            run(["defaults", "delete", "-g", "AppleInterfaceStyle"])
        run(["killall", "cfprefsd"])


# --- Linux -----------------------------------------------------------------

def linux_current() -> str:
    res = run([
        "gsettings", "get", "org.gnome.desktop.interface", "color-scheme",
    ])
    return "dark" if res.stdout.strip().strip("'") == "prefer-dark" else "light"


def linux_set(mode: str) -> None:
    value = "prefer-dark" if mode == "dark" else "prefer-light"
    run([
        "gsettings", "set", "org.gnome.desktop.interface", "color-scheme", value,
    ])
    # Keep the noctalia/niri desktop in sync when its hook is available.
    sync = Path.home() / ".config/noctalia/scripts/sync-system-appearance"
    if sync.exists():
        run([str(sync), mode])


# --- dispatch --------------------------------------------------------------

def toggle() -> str:
    system = platform.system()
    if system == "Darwin":
        current, apply = macos_current(), macos_set
    elif system == "Linux":
        current, apply = linux_current(), linux_set
    else:
        raise RuntimeError(f"unsupported system: {system}")
    target = "light" if current == "dark" else "dark"
    apply(target)
    return target


def main() -> int:
    try:
        target = toggle()
    except Exception as exc:  # noqa: BLE001 - surface any failure to the HUD
        print(f"Failed to toggle appearance: {exc}")
        return 1
    # First stdout line is shown in the compact HUD; Vicinae picks up the new
    # appearance automatically (no explicit `theme set` needed).
    print(f"Appearance: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())