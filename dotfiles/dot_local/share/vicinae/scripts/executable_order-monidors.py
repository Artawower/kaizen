#!/usr/bin/python3

# @vicinae.schemaVersion 1
# @vicinae.title Order Yabai Spaces
# @vicinae.icon 🖥️
# @vicinae.mode compact
# @vicinae.description Move work spaces to the preferred display
# @vicinae.keywords ["yabai", "spaces", "display", "monitor"]

import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

BUILTIN_DISPLAY_UUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
EXTERNAL_DISPLAY_UUID = "949551E3-16D5-43D9-A047-3C27967A2B50"

MANAGED_SPACES = (
    "dev",
    "other",
    "entertainment",
    "thrash",
    "study",
    "ai",
    "load",
)


def find_yabai():
    paths = (
        Path.home() / ".nix-profile/bin/yabai",
        Path("/opt/homebrew/bin/yabai"),
        Path("/usr/local/bin/yabai"),
    )

    for path in paths:
        if path.is_file():
            return str(path)

    raise RuntimeError("yabai not found")


YABAI = find_yabai()


def yabai(*args):
    return subprocess.run(
        [YABAI, "-m", *args],
        capture_output=True,
        text=True,
    )


def query(name):
    result = yabai("query", "--" + name)

    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip() or result.stdout.strip() or "Failed to query " + name
        )

    return json.loads(result.stdout)


def get_display(displays, uuid):
    return next(
        (display for display in displays if display["uuid"] == uuid),
        None,
    )


def main():
    try:
        displays = query("displays")
        spaces = query("spaces")

        builtin = get_display(
            displays,
            BUILTIN_DISPLAY_UUID,
        )

        external = get_display(
            displays,
            EXTERNAL_DISPLAY_UUID,
        )

        target = builtin or external

        if target is None:
            print("No target display available")
            return 0

        target_index = target["index"]

        spaces_by_label = {space["label"]: space for space in spaces if space["label"]}

        moved = 0

        for label in MANAGED_SPACES:
            space = spaces_by_label.get(label)

            if space is None:
                continue

            if space["display"] == target_index:
                continue

            result = yabai(
                "space",
                label,
                "--display",
                str(target_index),
            )

            if result.returncode != 0:
                error = (
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "unknown yabai error"
                )

                print("Failed: " + label + ": " + error)
                return 0

            moved += 1

        display_name = "built-in" if builtin is not None else "external"

        if moved:
            print("Spaces → " + display_name + ": " + str(moved) + " moved")
        else:
            print("Spaces already on " + display_name)

        return 0

    except Exception as error:
        print("Failed: " + str(error))
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
