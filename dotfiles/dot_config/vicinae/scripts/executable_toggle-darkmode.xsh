#!/usr/bin/env python3
# @vicinae.schemaVersion 1
# @vicinae.title Toggle Dark Mode
# @vicinae.mode silent

import json
import subprocess
from pathlib import Path

NOCTALIA_SETTINGS = Path.home() / ".config/noctalia/settings.json"
SYNC_APPEARANCE = Path.home() / ".config/noctalia/scripts/sync-system-appearance"


def notify(title: str, body: str = "") -> None:
    subprocess.run([
        "notify-send",
        "-t", "1200",
        "-u", "low",
        title,
        body,
    ], check=False)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, capture_output=True)


def current_noctalia_mode() -> str:
    try:
        data = json.loads(NOCTALIA_SETTINGS.read_text())
        return "dark" if data.get("colorSchemes", {}).get("darkMode", True) else "light"
    except Exception:
        return "dark"


def set_noctalia_settings_mode(mode: str) -> None:
    try:
        data = json.loads(NOCTALIA_SETTINGS.read_text())
        color_schemes = data.setdefault("colorSchemes", {})
        color_schemes["darkMode"] = mode == "dark"
        NOCTALIA_SETTINGS.write_text(json.dumps(data, indent=4) + "\n")
    except Exception:
        pass


def main() -> int:
    current = current_noctalia_mode()
    mode = "light" if current == "dark" else "dark"
    ipc_function = "setDark" if mode == "dark" else "setLight"

    try:
        set_noctalia_settings_mode(mode)
        run(["qs", "-c", "noctalia-shell", "-n", "ipc", "call", "darkMode", ipc_function])
    except Exception as exc:
        notify("Failed to toggle dark mode", str(exc))
        return 1

    # Noctalia's darkModeChange hook also runs this on the IPC call above; invoke
    # it explicitly too so the system stays in sync even if hooks are disabled.
    run([str(SYNC_APPEARANCE), mode], check=False)
    notify("Dark mode" if mode == "dark" else "Light mode")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
