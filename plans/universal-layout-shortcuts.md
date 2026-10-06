# Universal Layout and Shortcut Architecture

Status: proposed (future backlog)

## Problem

`layout` currently conflates two independent concerns:

1. **Typing layout (OS input layer)**: XKB rules on Linux (`xkb_rules_variant=colemak,`) or Input Source on macOS.
2. **Navigation and shortcut profile**: Directional keys (`h/j/k/l` vs `h/n/e/i` vs `d/h/t/n`) and application action bindings.

Additionally, workspace direct-jump letters (e.g. `s, t, w, d, o, r, u, l, a` vs `s, t, w, d, i, e, x, u, a`) are hardcoded directly into window manager templates (`mango/config.conf.tmpl`) within `{{ if eq .layout "colemak" }}` conditionals.

This creates several issues:

- A user wanting Colemak for typing but vanilla `h/j/k/l` navigation cannot configure this without manually overriding dozens of shortcut keys.
- Adding a new layout (e.g. Dvorak, Colemak-DH, Workman) requires modifying multiple dotfile templates (`mango`, `aerospace`, `zellij`, `yazi`, `gitu`, `skhd`).
- Template files contain hardcoded conditionals duplicating 50+ lines of bindings across files.
- `dotfiles/.chezmoidata.toml` bakes Colemak bindings statically into `[kaizen.shortcuts]` instead of dynamically resolving them from the user's active configuration.
- Workspace letter keys do not belong in generic application shortcuts (`[kaizen.shortcuts]` is strictly for semantic actions like `nav.*`, `file.*`, `vcs.*`), but rather in layout-specific workspace mappings.

## Goal

- Decouple OS typing layout from the navigation/shortcut preset in user configuration.
- Support arbitrary combinations (e.g. `layout = "colemak"` with `shortcuts = "qwerty"`).
- Make shortcut resolution fully data-driven: adding a new layout or shortcut scheme requires only adding data in TOML, without touching templates.
- Allow each layout to declare its own workspace letter bindings corresponding to semantic workspace tags (`SOC`, `TRM`, `WEB`, etc.).
- Unify templates to consume resolved shortcuts and layout metadata without layout branching.

## Proposed User Configuration

In `~/.config/kaizen/config.toml`:

```toml
# Typing layout for OS input (xkb / macOS)
layout = "colemak"

# Navigation / shortcut preset: "colemak", "qwerty" (vanilla hjkl), "dvorak"
# Defaults to matching layout when omitted
shortcuts = "qwerty"

# Optional granular user overrides on top of the resolved preset
[kaizen.shortcuts]
"nav.down" = ["j"]
```

## Architecture

### 1. Workspace Definition & Layout-Specific Key Mappings

Workspace names are declared semantically in `[ui].workspaces` (as introduced for UI bars and widgets):

```toml
[ui]
workspaces = [
  "SOC",
  "TRM",
  "WEB",
  "DEV",
  "ENT",
  "THR",
  "STU",
  "AI",
  "PRD",
]
```

Each layout defines its own workspace jump keys. This reflects keyboard physical geometry and avoids collisions with layout-specific navigation keys (e.g. in Colemak, `e` and `i` are occupied by `nav.up` and `nav.right`, so `ENT` and `THR` use alternate mnemonic keys `o` and `r`):

```toml
[keyboard.layouts.qwerty]
xkb_variant = ""

[keyboard.layouts.qwerty.workspaces]
SOC = "s"
TRM = "t"
WEB = "w"
DEV = "d"
ENT = "i"
THR = "e"
STU = "x"
AI  = "u"
PRD = "a"

[keyboard.layouts.colemak]
xkb_variant = "colemak,"

[keyboard.layouts.colemak.workspaces]
SOC = "s"
TRM = "t"
WEB = "w"
DEV = "d"
ENT = "o"
THR = "r"
STU = "u"
AI  = "l"
PRD = "a"
```

### 2. Semantic Shortcut Presets in `.chezmoidata.toml`

Application shortcuts are purely semantic actions and do not contain window manager workspace tags:

```toml
[shortcuts.presets.qwerty]
"nav.left" = ["h"]
"nav.down" = ["j"]
"nav.up" = ["k"]
"nav.right" = ["l"]
"nav.insert" = ["i"]

[shortcuts.presets.colemak]
"nav.left" = ["h"]
"nav.down" = ["n"]
"nav.up" = ["e"]
"nav.right" = ["i"]
"nav.insert" = ["l"]
```

### 3. Dynamic Resolution in `kaizen.py`

During `kaizen sync`:

1. Read `active_layout = config.get("layout", "qwerty")`.
2. Read `active_shortcuts = config.get("shortcuts", active_layout)`.
3. Resolve shortcuts by layering:
   `base_shortcuts` -> `shortcuts.presets[active_shortcuts]` -> `user[kaizen.shortcuts]`.
4. Resolve keyboard metadata and active workspace keymap:
   `xkb_variant = keyboard.layouts[active_layout].xkb_variant`.
   `workspace_keys = keyboard.layouts[active_layout].workspaces`.
5. Write the resolved data to `.chezmoidata/99-user.toml` before invoking `chezmoi apply`.

### 4. Template Unification

Remove `{{ if eq .layout "colemak" }}` branching from all templates:

- **MangoWM (`dot_config/mango/config.conf.tmpl`)**:
  - `xkb_rules_variant={{ .keyboard.xkb_variant }}`
  - Directional binds reference `{{ index .kaizen.shortcuts "nav.left" }}`, `{{ index .kaizen.shortcuts "nav.down" }}`, etc.
  - Workspace binds loop over `.ui.workspaces` with both numerical (`1..9`) and layout-provided letter keys (`index .keyboard.active_workspaces $ws`).
- **AeroSpace (`dot_config/aerospace/aerospace.toml.tmpl`)**:
  - Use `nav.*` shortcuts for focus, move, and resize directions.
- **Zellij (`dot_config/zellij/config.kdl.tmpl`)**:
  - Unify into a single templated config or include by preset name rather than bifurcated static files.
- **Yazi (`dot_config/yazi/keymap.toml.tmpl`)** and **Gitu (`dot_config/gitu/config.toml.tmpl`)**:
  - Consume `.kaizen.shortcuts` directly.

## Implementation Steps

1. **Presets & Schema**: Add `[keyboard.layouts]` and `[shortcuts.presets]` to `dotfiles/.chezmoidata.toml` and document in `config.example.toml`.
2. **Resolver**: Implement preset overlay merging, layout workspace mapping, and keyboard metadata injection in `kaizen.py`.
3. **Template Refactoring**: Replace layout conditionals in `mango`, `aerospace`, `zellij`, `yazi`, `gitu`, and `skhd`.
4. **Verification**: Update test fixtures (`tests/mango-config.sh`, `tests/aerospace-config.sh`) and verify across `qwerty`, `colemak`, and mixed configurations.
