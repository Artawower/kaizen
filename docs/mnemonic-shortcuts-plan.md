> [!WARNING]
> DEPRECATED: This was a planning document. The implemented solution uses
> `keybindings.toml` (renamed from `mnemonics.toml`) with output schema
> `[kaizen.shortcuts]`. See `docs/shortcut-registry.md` for current state.

# Mnemonic shortcuts plan

Status: active. The semantic keymap experiment was replaced by this simpler approach.

## Problem

Kaizen wants consistent shortcut mnemonics across tools without owning every application's keybinding system.

The problem is not rendering shortcuts. Each application already has its own native format and usually knows its own leader/prefix.

The useful shared layer is only this:

```text
projects.pick    = p p
vcs.ui           = g g
pane.split.right = w v
pane.split.down  = w s
```

## Goal

Create a small shared mnemonic catalog that feature authors and dotfile templates can consult.

Kaizen should define the vocabulary of shortcut mnemonics, not become a shortcut renderer.

## Non-goals

Do not add:

- host adapters;
- global shortcut host selection;
- command registry;
- prefix/leader registry;
- generated skhd/aerospace/niri configs;
- universal modal/prefix engine;
- migration of every application shortcut.

## Public model

```text
Action id -> mnemonic path
```

A mnemonic path is abstract. Each consumer renders it in its own surface:

| Surface                | Example rendering for `projects.pick = "p p"`                |
| ---------------------- | ------------------------------------------------------------ |
| Modal editor leader    | `SPACE p p`                                                  |
| Shell alias            | `pp`                                                         |
| Global shortcut daemon | `<global-prefix> p p` if supported, or a local equivalent    |
| Emacs                  | Whatever elisp binds for `(kaizen-shortcut "projects.pick")` |

This means shell aliases can participate in the same vocabulary without turning
Kaizen into an alias manager.

Example (current accepted catalog):

```text
projects.pick    = p p
pane.split.right = w v
pane.split.down  = w s
vcs.ui           = g g
```

## Current catalog (first batch — accepted)

Only high-confidence entries that already exist in at least one consumer:

```toml
# dotfiles/kaizen/mnemonics.toml

[shortcuts]
"projects.pick"    = "p p"  # Zed space-p-p, Xonsh pp alias (zoxide zi)
"pane.split.right" = "w v"  # Helix/Zed space w v — already matches, no change needed
"pane.split.down"  = "w s"  # Helix/Zed space w s — already matches, no change needed
"vcs.ui"           = "g g"  # Helix/Zed space g g — already matches, no change needed
```

## Deferred (not in catalog yet)

| Action id        | Candidate mnemonic       | Reason deferred                                                        |
| ---------------- | ------------------------ | ---------------------------------------------------------------------- |
| `window.focus.*` | `nav.left/down/up/right` | Nav tokens need layout resolution; no consumer yet                     |
| `files.find`     | `f f`                    | Helix/Zed naming inconsistency (`ff` vs `space space`); needs decision |
| `vcs.status`     | `v s` vs `g s`           | VCS prefix `v` vs `g` undecided                                        |
| `vcs.diff`       | `v d` vs `g d`           | Same prefix conflict                                                   |
| `vcs.log`        | `v l` vs `g l`           | Same prefix conflict                                                   |

## Chezmoi template access

During `kaizen apply` / `kaizen sync`, the `[shortcuts]` table is exported
into the chezmoi source `.chezmoidata.toml` under `[kaizen.mnemonics.shortcuts]`:

```toml
[kaizen.mnemonics.shortcuts]
"projects.pick"    = "p p"
"pane.split.right" = "w v"
"pane.split.down"  = "w s"
"vcs.ui"           = "g g"
```

Any chezmoi template can then read a mnemonic:

```gotemplate
{{ index .kaizen.mnemonics.shortcuts "projects.pick" }}
```

No template helpers, host adapters, or generated files are needed.

## How applications use it

Each application keeps ownership of:

- its prefix/leader;
- native keybinding syntax;
- command implementation;
- compacting/expanding mnemonic paths for its surface;
- edge cases and app-specific shortcuts.

### Helix / chezmoi example

Helix already knows that space is its leader context.

```toml
[keys.normal.space.p]
p = "file_picker"
```

A future template helper could replace only the mnemonic lookup, not the command or leader ownership.

### skhd / chezmoi example

skhd knows its global modifier in its own config.

```gotemplate
ralt + rshift - {{ nav "left" }} : <wm focus left command>
```

Kaizen does not need to store `ralt + rshift` globally.

### Emacs example

Emacs does not need chezmoi templating if elisp can read the catalog directly.

```elisp
;; conceptually:
;; (kaizen-shortcut "projects.pick") -> "p p"
```

Emacs remains responsible for leader setup and command binding.

### Xonsh alias example

Shell aliases do not have modal key sequences, but they can still use the same
mnemonic path by compacting it.

```text
projects.pick = "p p" -> alias pp="zi"   # accepted; pp already live in zoxide.xsh
pane.split.*  = "w v"/"w s" -> no shell alias needed (editor-native)
vcs.ui        = "g g" -> no shell alias needed (editor-native)
```

Xonsh owns the alias command and whether a mnemonic is worth exposing as an
alias. Kaizen only names the action and the mnemonic.

## Minimal validation

Keep validation small:

1. duplicate shortcut ids are errors;
2. empty mnemonic values are errors;
3. unknown `nav.*` token is an error if nav mappings are declared (nav tokens are deferred);
4. duplicate mnemonic values are warnings, not errors.

Do not parse native app configs.

Validation code (Rust module in `kaizen-core`) is not added yet — there is no
Rust consumer today. Add it when a real consumer or CI check appears.

## Migration strategy

1. Add `dotfiles/kaizen/mnemonics.toml` with a small catalog.
2. Use it in one low-risk template or script.
3. Do not migrate Emacs initially.
4. Do not remove native shortcuts during the experiment.
5. If it stays useful, gradually replace hardcoded mnemonic strings in selected templates.

## Success criteria

The approach is worth keeping only if it makes configs easier to read.

Good sign:

```text
This shortcut follows the shared mnemonic catalog.
```

Bad sign:

```text
I need to understand a new framework before editing one shortcut.
```

If the bad sign appears, keep native app configs and drop the abstraction.
