# Shortcuts

## Modifier grammar

| Container           | Modifier      | Direction set                       |
| ------------------- | ------------- | ----------------------------------- |
| OS / WM             | `Caps`        | Full: h / j / k / l                 |
| Pane / View         | `Ctrl + Alt`  | Full: h / j / k / l                 |
| Tab / Buffer        | `Cmd + Shift` | Horizontal pair: h = prev, l = next |
| Workspace / Session | `Cmd + Shift` | Vertical pair: k = prev, j = next   |

Same modifier `Cmd+Shift` — direction keys distinguish tabs (horizontal) from workspaces (vertical).

**Spatial navigation** (windows, splits, panes) — full 4-direction set.  
**Linear navigation** (tabs, workspaces) — direction pair only.

Colemak remaps `j→n`, `k→e`, `l→i`; `h` stays.

Known conflicts requiring per-app rebind:

- `Cmd+Shift+N` — Finder "New Folder" (not rebound)
- `Cmd+Shift+I` — Inspector in some apps (rebind in Zen browser)

---

## Direction keys

| Direction     | QWERTY | Colemak |
| ------------- | :----: | :-----: |
| Left          |  `h`   |   `h`   |
| Down / Next   |  `j`   |   `n`   |
| Up / Previous |  `k`   |   `e`   |
| Right         |  `l`   |   `i`   |

---

## Tiling / WM

Handled by: **Aerospace** (macOS), **Niri** (Linux).

| Action                | QWERTY        | Colemak       |
| --------------------- | ------------- | ------------- |
| Focus left            | `Caps + h`    | `Caps + h`    |
| Focus down            | `Caps + j`    | `Caps + n`    |
| Focus up              | `Caps + k`    | `Caps + e`    |
| Focus right           | `Caps + l`    | `Caps + i`    |
| Switch workspace by № | `Caps + 1..9` | `Caps + 1..9` |

---

## Terminal multiplexer

Handled by: **herdr**, **Zellij**.

| Action                | QWERTY                   | Colemak                  |
| --------------------- | ------------------------ | ------------------------ |
| Focus pane left       | `Ctrl + Alt + h`         | `Ctrl + Alt + h`         |
| Focus pane down       | `Ctrl + Alt + j`         | `Ctrl + Alt + n`         |
| Focus pane up         | `Ctrl + Alt + k`         | `Ctrl + Alt + e`         |
| Focus pane right      | `Ctrl + Alt + l`         | `Ctrl + Alt + i`         |
| Move pane left        | `Ctrl + Alt + Shift + h` | `Ctrl + Alt + Shift + h` |
| Move pane down        | `Ctrl + Alt + Shift + j` | `Ctrl + Alt + Shift + n` |
| Move pane up          | `Ctrl + Alt + Shift + k` | `Ctrl + Alt + Shift + e` |
| Move pane right       | `Ctrl + Alt + Shift + l` | `Ctrl + Alt + Shift + i` |
| Previous tab          | `Cmd + Shift + h`        | `Cmd + Shift + h`        |
| Next tab              | `Cmd + Shift + l`        | `Cmd + Shift + i`        |
| Previous workspace    | `Cmd + Shift + k`        | `Cmd + Shift + e`        |
| Next workspace        | `Cmd + Shift + j`        | `Cmd + Shift + n`        |
| Switch workspace by № | `Cmd + Shift + 1..9`     | `Cmd + Shift + 1..9`     |

herdr also binds `prefix + <nav key>` as alias for all tab/workspace actions.

---

## Apps

Handled by: **Helix**, **Zed**, **Ghostty**, and other GUI apps.

### Pane / split focus

| Action           | QWERTY                   | Colemak                  |
| ---------------- | ------------------------ | ------------------------ |
| Focus pane left  | `Ctrl + Alt + h`         | `Ctrl + Alt + h`         |
| Focus pane down  | `Ctrl + Alt + j`         | `Ctrl + Alt + n`         |
| Focus pane up    | `Ctrl + Alt + k`         | `Ctrl + Alt + e`         |
| Focus pane right | `Ctrl + Alt + l`         | `Ctrl + Alt + i`         |
| Move pane left   | `Ctrl + Alt + Shift + h` | `Ctrl + Alt + Shift + h` |
| Move pane down   | `Ctrl + Alt + Shift + j` | `Ctrl + Alt + Shift + n` |
| Move pane up     | `Ctrl + Alt + Shift + k` | `Ctrl + Alt + Shift + e` |
| Move pane right  | `Ctrl + Alt + Shift + l` | `Ctrl + Alt + Shift + i` |

### Tab / buffer

| Action              | QWERTY            | Colemak           |
| ------------------- | ----------------- | ----------------- |
| Previous tab/buffer | `Cmd + Shift + h` | `Cmd + Shift + h` |
| Next tab/buffer     | `Cmd + Shift + l` | `Cmd + Shift + i` |
| Switch tab by №     | `Cmd + 1..9`      | `Cmd + 1..9`      |

### Workspace / session

| Action                | QWERTY               | Colemak              |
| --------------------- | -------------------- | -------------------- |
| Previous workspace    | `Cmd + Shift + k`    | `Cmd + Shift + e`    |
| Next workspace        | `Cmd + Shift + j`    | `Cmd + Shift + n`    |
| Switch workspace by № | `Cmd + Shift + 1..9` | `Cmd + Shift + 1..9` |
