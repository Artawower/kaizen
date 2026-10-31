# Shortcuts

## Modifier grammar

| Container           | Modifier      | Direction set                                          |
| ------------------- | ------------- | ------------------------------------------------------ |
| OS / WM             | `Caps`        | Full: h / j / k / l                                    |
| Multiplexer pane    | `Alt`         | Full: h / j / k / l (TUIOS, stays in multiplexer) |
| App pane / split    | `Ctrl + Alt`  | Full: h / j / k / l (passes through multiplexer)       |
| Tab / Buffer        | `Cmd + Shift` | Horizontal pair: h = prev, l = next                    |
| Workspace / Session | `Cmd + Shift` | Vertical pair: k = prev, j = next                      |

Same modifier `Cmd+Shift` — direction keys distinguish tabs (horizontal) from workspaces (vertical).

**Spatial navigation** (windows, splits, panes) — full 4-direction set.  
**Linear navigation** (tabs, workspaces) — direction pair only.

TUIOS binds logical characters: `h/j/k/l` stay `h/j/k/l` in Colemak.
The position table below describes physical keys, not TUIOS binding names.

Known conflicts requiring per-app rebind:

- `Cmd+Shift+N` — Finder "New Folder" (not rebound)
- `Cmd+Shift+I` — Inspector in some apps (rebind in Zen browser)

---

## Direction keys

| Direction     | QWERTY position | Colemak character |
| ------------- | :----: | :-----: |
| Left          |  `h`   |   `h`   |
| Down / Next   |  `j`   |   `n`   |
| Up / Previous |  `k`   |   `e`   |
| Right         |  `l`   |   `i`   |

---

## Tiling / WM

Handled by: **Yabai / Rift** (macOS), **Niri / MangoWM** (Linux).

| Action                | QWERTY        | Colemak       |
| --------------------- | ------------- | ------------- |
| Focus left            | `Caps + h`    | `Caps + h`    |
| Focus down            | `Caps + j`    | `Caps + n`    |
| Focus up              | `Caps + k`    | `Caps + e`    |
| Focus right           | `Caps + l`    | `Caps + i`    |
| Switch workspace by № | `Caps + 1..9` | `Caps + 1..9` |

---

## Terminal multiplexer

Handled by: **TUIOS** (`prefix = Ctrl+B`).

Herdr workspaces become TUIOS sessions; herdr tabs become TUIOS workspaces;
herdr panes become TUIOS windows. All keys below are logical characters in
any Latin layout. Command bindings also have the Russian aliases from
`config.example.toml`.

On macOS the TUIOS layer is `Caps+Cmd` (`Cmd+Alt+Shift`); on Linux it is `Ctrl+Alt+Shift`.

| Action | Keys |
| ------ | ---- |
| Focus pane left / down / up / right | `Caps+Cmd+h/j/k/l` |
| Previous / next tab (TUIOS workspace) | `Cmd+Shift+h/l` |
| Select tab by index | `Caps+Cmd+1..9` or `prefix 1..9` |
| Previous / next session | `Cmd+Shift+k/j` |
| Select session by index | `Ctrl+1..9` |
| Pick session | `Caps+Cmd+w` or `prefix w` |
| New session | `Cmd+Shift+w` or `prefix Shift+n` |
| Rename / close session | `Cmd+Shift+r/d` |
| New tab | `Caps+Cmd+t` or `prefix c` |
| Rename / close tab | `Caps+Cmd+r/x` |
| Split right / below | `prefix v` / `prefix -` |
| Close pane | `Caps+Cmd+d` or `prefix x` |
| Zoom / restore pane | `Caps+Cmd+f` or `prefix f` |
| Toggle sidebar | `prefix b` |
| Reload config | `prefix Shift+r` |
| Detach without stopping panes | `prefix q` |
| Equalize splits | `prefix Shift+e` |
| Arrange a tiled grid | `prefix Alt+5` |
| Resize left / down / up / right by five cells | `prefix Alt+h/j/k/l` |
| Open resize/layout menu | `prefix r`, then `h/j/k/l` |

`Ctrl+Alt+direction` remains available to the application inside the pane.
See [TUIOS migration](tuios.md) for deployment, changed defaults and limitations.

---

## Apps

Handled by: **Helix**, **Zed**, and other GUI apps.

`Ctrl+Alt+nav` passes through the multiplexer to the focused app.

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

### Workspace / project

| Action             | QWERTY            | Colemak           |
| ------------------ | ----------------- | ----------------- |
| Previous workspace | `Cmd + Shift + k` | `Cmd + Shift + e` |
| Next workspace     | `Cmd + Shift + j` | `Cmd + Shift + n` |
