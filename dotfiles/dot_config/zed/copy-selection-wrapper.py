#!/usr/bin/env python3

import os
import pathlib
import subprocess

path_s = os.environ.get("ZED_FILE")
row_s = os.environ.get("ZED_ROW")
text = os.environ.get("ZED_SELECTED_TEXT") or ""

if not path_s:
    raise SystemExit("No ZED_FILE. Focus a saved editor buffer first.")

if not text:
    raise SystemExit("No ZED_SELECTED_TEXT. Select text before running this task.")

path = pathlib.Path(path_s).resolve()
row = int(row_s) if row_s and row_s.isdigit() else None

try:
    src = path.read_text(errors="replace")
except Exception:
    src = ""

def line_count(s: str) -> int:
    if not s:
        return 1
    return s.count("\n") if s.endswith("\n") else s.count("\n") + 1

matches = []
pos = 0

while src:
    idx = src.find(text, pos)
    if idx < 0:
        break

    start = src.count("\n", 0, idx) + 1
    end = start + line_count(text) - 1
    matches.append((start, end, idx))
    pos = idx + 1

if matches:
    if row is not None:
        chosen = (
            next((m for m in matches if m[0] <= row <= m[1]), None)
            or min(matches, key=lambda m: abs(m[0] - row))
        )
    else:
        chosen = matches[0]

    start, end, _ = chosen
else:
    start = end = row if row is not None else "?"

out = f"{path}:{start}-{end}\n{text}"

subprocess.run(["pbcopy"], input=out, text=True, check=True)
print("Copied:", out.split("\n", 1)[0])
