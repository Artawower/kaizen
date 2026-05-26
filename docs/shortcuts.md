# Shortcuts

## Modifier grammar

The modifier encodes the container level; the direction encodes the movement.

| Container           | Modifier     | Direction set                         |
| ------------------- | ------------ | ------------------------------------- |
| OS / WM             | `Caps`       | Full: h / j / k / l                   |
| Pane / View         | `Ctrl + Alt` | Full: h / j / k / l                   |
| Tab / Buffer        | `Cmd + Alt`  | Linear: k = prev, j = next + `Cmd+№`  |
| Workspace / Session | `Ctrl`       | Linear: k = prev, j = next + `Ctrl+№` |

**Spatial navigation** (windows, splits, panes) — full 4-direction set.  
**Linear navigation** (tabs, buffers, workspaces, sessions) — vertical pair only: `k` = previous, `j` = next.

Colemak remaps `j→n`, `k→e`, `l→i`; `h` stays.

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

Handled by: **Zellij**, **tmux**.

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

| Action              | QWERTY          | Colemak         |
| ------------------- | --------------- | --------------- |
| Previous tab/buffer | `Cmd + Alt + k` | `Cmd + Alt + e` |
| Next tab/buffer     | `Cmd + Alt + j` | `Cmd + Alt + n` |
| Switch tab by №     | `Cmd + 1..9`    | `Cmd + 1..9`    |

### Workspace / session

> App-level only. `Ctrl + j/k` conflict with readline in raw terminal
> (Enter / kill-to-EOL) — register only in GUI application keymaps.

| Action                | QWERTY        | Colemak       |
| --------------------- | ------------- | ------------- |
| Previous workspace    | `Ctrl + k`    | `Ctrl + e`    |
| Next workspace        | `Ctrl + j`    | `Ctrl + n`    |
| Switch workspace by № | `Ctrl + 1..9` | `Ctrl + 1..9` |
