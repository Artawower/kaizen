#!/usr/bin/env bash
set -euo pipefail

python3 <<'PY'
import json
import subprocess


def rex(*args):
    result = subprocess.run(["rex", *args], check=True, capture_output=True, text=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


created = rex("new", "kaizen-scratch-test", "--shell=none", "--json", "--", "/bin/cat")
session = created["session_id"]
block = created["initial_windows"][0]["block_ids"][0]


def view():
    state = rex("api", "call", "session.view", json.dumps({"session_id": session}))
    return next(window for window in state["windows"] if window["window_id"] == state["active_window_id"])


def toggle():
    rex("do", "-s", session, "scratch_toggle", "--json")


try:
    rex("split", "-b", block, "--focus=false", "--shell=none", "--json", "--", "/bin/cat")
    for zoomed in (True, True, False, False, True):
        rex("api", "call", "session.zoom_block", json.dumps({"session_id": session, "block_id": block, "zoom": zoomed}))
        before = view()
        toggle()
        opened = view()
        scratch = next(layer for layer in opened["layers"] if layer["kind"] == "floating")
        assert scratch.get("state") != "minimized", "scratch did not open"
        assert opened["focused_block_id"] == scratch["blocks"][0]["block_id"]
        toggle()
        after = view()
        assert after.get("zoomed_block_id") == before.get("zoomed_block_id"), "scratch cycle lost full size"
        assert after["focused_block_id"] == before["focused_block_id"], "scratch cycle lost focus"
        assert after["layers"][0] == before["layers"][0], "scratch cycle changed tiled layout"
    first_window = view()["window_id"]
    toggle()
    second = rex("window", "new", "-s", session, "Other", "--shell=none", "--json", "--", "/bin/cat")
    second_block = second["block_ids"][0]
    rex("api", "call", "session.zoom_block", json.dumps({"session_id": session, "block_id": second_block, "zoom": True}))
    toggle()
    for window_id, expected_block in ((first_window, block), (second["window_id"], second_block)):
        rex("api", "call", "session.focus_window", json.dumps({"session_id": session, "window_id": window_id}))
        toggle()
        assert view().get("zoomed_block_id") == expected_block, "scratch mixed zoom between tabs"
    print("Scratch creation, reuse, focus, layout, zoom and tab isolation checks passed")
finally:
    rex("kill", session)
PY
