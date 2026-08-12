#!/usr/bin/python3

# @vicinae.schemaVersion 1
# @vicinae.title Order Monitors
# @vicinae.icon 🖥️
# @vicinae.mode compact
# @vicinae.description Restore yabai spaces across displays
# @vicinae.keywords ["yabai", "spaces", "display", "monitor"]

import json
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

MONITORS = {
    "left": "949551E3-16D5-43D9-A047-3C27967A2B50",
    "right": "BE7AE1C8-EAFC-4690-8DA5-F527C9F86DE7",
    "builtin": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
}

SPACE_ORDER = (
    "social",
    "term",
    "www",
    "dev",
    "other",
    "entertainment",
    "thrash",
    "study",
    "ai",
    "load",
)

LAYOUTS = (
    (
        ("left", "right"),
        (
            ("left", 3),
            ("right", None),
        ),
    ),
    (
        ("right", "builtin"),
        (
            ("right", 3),
            ("builtin", None),
        ),
    ),
    (
        ("left", "right", "builtin"),
        (
            ("left", 1),
            ("right", 3),
            ("builtin", None),
        ),
    ),
)

DEBUG = "--debug" in sys.argv


def log(message):
    if DEBUG:
        print(message)


def find_yabai():
    for path in (
        Path("/opt/homebrew/bin/yabai"),
        Path("/usr/local/bin/yabai"),
    ):
        if path.is_file():
            return str(path)

    raise RuntimeError("yabai not found")


YABAI = find_yabai()


def yabai(*args):
    result = subprocess.run(
        [YABAI, "-m", *args],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip() or result.stdout.strip() or "yabai command failed"
        )

    return result


def query(name):
    output = yabai("query", "--" + name).stdout
    return json.JSONDecoder().decode(output)


def get_active_monitors(displays):
    displays_by_uuid = {display["uuid"]: display for display in displays}

    return {
        name: displays_by_uuid[uuid]
        for name, uuid in MONITORS.items()
        if uuid in displays_by_uuid
    }


def get_layout(active):
    if len(active) == 1:
        name = next(iter(active))
        return ((name, None),)

    active_names = set(active)

    for monitors, layout in LAYOUTS:
        if set(monitors) == active_names:
            return layout

    raise RuntimeError("No layout configured for: " + ", ".join(sorted(active_names)))


def sort_spaces(spaces):
    order = {label: index for index, label in enumerate(SPACE_ORDER)}

    known = []
    unknown = []

    for space in spaces:
        if space["label"] in order:
            known.append(space)
        else:
            unknown.append(space)

    known.sort(key=lambda space: order[space["label"]])

    unknown.sort(key=lambda space: space["index"])

    return known + unknown


def build_plan(spaces, active, layout):
    spaces = sort_spaces(spaces)

    plan = {}
    offset = 0

    rest_seen = False

    for monitor_name, count in layout:
        if monitor_name not in active:
            raise RuntimeError(f"Monitor is not active: {monitor_name}")

        if count is None:
            if rest_seen:
                raise RuntimeError("Layout can contain only one None")

            count = len(spaces) - offset
            rest_seen = True

        if count < 1:
            raise RuntimeError("Every active monitor must have at least one space")

        group = spaces[offset : offset + count]

        target_uuid = active[monitor_name]["uuid"]

        for space in group:
            plan[space["uuid"]] = target_uuid

        offset += count

    if offset != len(spaces):
        raise RuntimeError(f"Layout covers {offset} of {len(spaces)} spaces")

    return plan


def get_move_candidate(displays, spaces, plan):
    displays_by_uuid = {display["uuid"]: display for display in displays}

    counts = Counter(space["display"] for space in spaces)

    for space in spaces:
        target_uuid = plan.get(space["uuid"])

        if target_uuid is None:
            continue

        target = displays_by_uuid.get(target_uuid)

        if target is None:
            raise RuntimeError(f"Target display disappeared: {target_uuid}")

        if space["display"] == target["index"]:
            continue

        if counts[space["display"]] <= 1:
            continue

        return space, target

    return None


def get_misplaced(displays, spaces, plan):
    displays_by_uuid = {display["uuid"]: display for display in displays}

    misplaced = []

    for space in spaces:
        target_uuid = plan.get(space["uuid"])

        if target_uuid is None:
            continue

        target = displays_by_uuid[target_uuid]

        if space["display"] != target["index"]:
            misplaced.append(space)

    return misplaced


def move_space(space, target):
    selector = space["label"] or str(space["index"])

    log(f"move {space['label'] or selector}: {space['display']} -> {target['index']}")

    yabai(
        "space",
        selector,
        "--display",
        str(target["index"]),
    )

    time.sleep(0.2)


def describe_layout(layout):
    return ", ".join(
        f"{monitor}={count if count is not None else 'rest'}"
        for monitor, count in layout
    )


def main():
    try:
        displays = query("displays")
        spaces = query("spaces")

        active = get_active_monitors(displays)
        layout = get_layout(active)

        plan = build_plan(
            spaces,
            active,
            layout,
        )

        log("active: " + ", ".join(active))

        log("layout: " + describe_layout(layout))

        moved = 0

        for _ in range(100):
            displays = query("displays")
            spaces = query("spaces")

            misplaced = get_misplaced(
                displays,
                spaces,
                plan,
            )

            if not misplaced:
                break

            candidate = get_move_candidate(
                displays,
                spaces,
                plan,
            )

            if candidate is None:
                labels = ", ".join(
                    space["label"] or str(space["index"]) for space in misplaced
                )

                raise RuntimeError(f"Cannot move remaining spaces: {labels}")

            space, target = candidate

            move_space(space, target)
            moved += 1

        else:
            raise RuntimeError("Too many iterations")

        displays = query("displays")
        spaces = query("spaces")

        misplaced = get_misplaced(
            displays,
            spaces,
            plan,
        )

        if misplaced:
            raise RuntimeError(f"{len(misplaced)} spaces are still misplaced")

        if moved:
            print(f"Spaces ordered: {moved} moved")
        else:
            print("Spaces already ordered")

        return 0

    except Exception as error:
        print(f"Failed: {error}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
