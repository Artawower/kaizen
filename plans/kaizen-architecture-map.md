> [!WARNING]
> DEPRECATED: This document predates the keybindings.toml rename.
> References to `mnemonics.toml` and `[kaizen.mnemonics.shortcuts]` are outdated.
> See `docs/architecture.md` for the current architecture.

# Kaizen public architecture map

This page is for a contributor who opens Kaizen for the first time. It describes the **public authoring model**: what a feature author can declare, how Kaizen combines declarations, and where shortcuts fit.

Diagram rule used here: **one diagram answers one question**. No mega-diagrams.

## 0. Mental model

Kaizen has three public layers:

```mermaid
flowchart LR
  Author["Feature author"] --> Declares["Declares capabilities"]
  User["User"] --> Selects["Selects desired state"]

  Declares --> Kaizen["Kaizen resolves selections"]
  Selects --> Kaizen

  Kaizen --> Outputs["Rendered environment"]
  Outputs --> Packages["Packages / services"]
  Outputs --> Dotfiles["Dotfiles"]
  Outputs --> Shortcuts["Shortcuts (app-native)"]
```

In plain words:

1. Feature authors declare what exists.
2. Users choose what they want.
3. Kaizen resolves choices into final packages, dotfiles, and hooks.
   Shortcuts stay in each application's own config.

---

## 1. Feature structure

A feature is the public unit of capability. It may contain atoms, slots, variants, hooks, packages, and dotfiles.

```mermaid
flowchart TB
  Feature["Feature"]
  Atom["Atom<br/>optional sub-part"]
  Slot["Slot<br/>choice point"]
  Variant["Variant<br/>implementation of slot"]
  Contributions["Contributions"]

  Feature --> Atom
  Feature --> Slot
  Slot --> Variant
  Feature --> Contributions
  Variant --> Contributions

  Contributions --> Nix["Nix packages/services"]
  Contributions --> Dotfiles["Dotfile templates/paths"]
  Contributions --> Hooks["Lifecycle hooks"]
```

### Example: feature with a slot

```toml
# features/tiling/feature.toml

title = "Tiling window manager"

[[slots]]
id = "wm"
required = true
description = "Window manager implementation"
```

### Example: variant implementing that slot

```toml
# features/tiling/variants/komorebi/variant.toml

id = "komorebi"
slot = "tiling.wm"
title = "komorebi-for-mac"
platforms = ["darwin"]
default = false

[provides]
nix_modules = ["module.darwin.nix"]
dotfile_paths = ["dot_config/komorebi/", "dot_config/skhd/skhdrc-komorebi"]

[hooks]
post_apply = ["komorebic start --bar || true"]
```

### What this means

- `tiling` is a feature.
- `tiling.wm` is a slot owned by `tiling`.
- `komorebi` is one possible implementation of `tiling.wm`.
- The active variant contributes packages, dotfiles, and hooks.

---

## 2. Feature entities

```mermaid
classDiagram
  class Feature {
    id
    title
    category
    atoms
    slots
    hooks
  }

  class Atom {
    id
    optional part of Feature
  }

  class Slot {
    id
    required?
    description
  }

  class Variant {
    id
    slot
    platforms
    default?
    provides
    hooks
  }

  class Contribution {
    nix modules
    dotfile paths
    hooks
  }

  Feature "1" --> "0..many" Atom
  Feature "1" --> "0..many" Slot
  Slot "1" --> "1..many" Variant
  Feature --> Contribution
  Variant --> Contribution
```

### Public contracts

| Entity       | Public contract                                                                 |
| ------------ | ------------------------------------------------------------------------------- |
| Feature      | Capability a user can enable or disable.                                        |
| Atom         | Optional sub-capability a user can disable without disabling the whole feature. |
| Slot         | Named choice point inside a feature.                                            |
| Variant      | One implementation of a slot. Only one variant is active per slot.              |
| Contribution | Something a feature or variant adds to the final system.                        |
| Hook         | Command attached to a lifecycle phase.                                          |

---

## 3. How modules are assembled

```mermaid
flowchart LR
  UserConfig["User config<br/>features, atoms, layout, variants"]
  FeatureCatalog["Feature catalog<br/>available features and variants"]
  Resolver["Resolver<br/>applies defaults and overrides"]
  EffectiveState["Effective state<br/>enabled features + active variants + layout"]
  Outputs["Outputs"]

  UserConfig --> Resolver
  FeatureCatalog --> Resolver
  Resolver --> EffectiveState

  EffectiveState --> Packages["Nix packages/services"]
  EffectiveState --> Templates["Chezmoi templates"]
  EffectiveState --> Hooks["Lifecycle hooks"]

  Packages --> Outputs
  Templates --> Outputs
  Hooks --> Outputs
```

### What gets resolved

```text
User says:       tiling enabled, layout = colemak
Feature says:    tiling has slot wm
Variants say:    wm can be yabai, komorebi, aerospace
Resolver says:   active variant is tiling.wm = komorebi
Outputs use:     enabled features + active variants + layout
```

---

## 4. Shortcuts: mnemonic catalog

Kaizen does **not** own application keybinding systems. Each application keeps its
prefix/leader, native syntax, and command binding.

The shared layer is a small **mnemonic catalog** in `dotfiles/kaizen/mnemonics.toml`.

Current accepted entries (first batch):

```toml
[shortcuts]
"projects.pick"    = "p p"
"pane.split.right" = "w v"
"pane.split.down"  = "w s"
"vcs.ui"           = "g g"
```

Deferred: `window.focus.*` (nav.\* keys accepted via layout overlay; no WM consumer yet), `files.find`, `vcs.status/diff/log`.
See `plans/mnemonic-shortcuts-plan.md` for the deferred list and blockers.

### Chezmoi template access

During `kaizen apply` / `kaizen sync`, the catalog is exported into
`.chezmoidata.toml` under `[kaizen.mnemonics.shortcuts]`:

```toml
[kaizen.mnemonics.shortcuts]
"projects.pick"    = "p p"
"pane.split.right" = "w v"
"pane.split.down"  = "w s"
"vcs.ui"           = "g g"
```

Chezmoi templates can then read any entry:

```gotemplate
{{ index .kaizen.mnemonics.shortcuts "projects.pick" }}
```

### Design principle

```text
Action id -> mnemonic path
```

Kaizen defines the vocabulary. Applications own the implementation and the
surface encoding. For example, `projects.pick = "p p"` can become `SPACE p p`
in an editor, `pp` in Xonsh, or an app-native binding in Emacs.

### What Kaizen does not do

- No shortcut rendering or generation.
- No host adapters (skhd/aerospace/niri).
- No command registry.
- No prefix/leader registry.
- No migration of every application shortcut.

See `plans/mnemonic-shortcuts-plan.md` for the full rationale.

---

## 5. Command behavior

```mermaid
flowchart TB
  Apply["kaizen apply"] --> ApplySteps["resolve desired state<br/>render dotfiles<br/>apply packages/hooks"]
  VariantSet["kaizen variant set"] --> VariantSteps["change slot selection<br/>next apply uses it"]
  Bump["kaizen bump"] --> BumpSteps["run update steps<br/>capture changed managed outputs<br/>run update hooks"]
```

### Public command expectations

| Command              | Public behavior                                                     |
| -------------------- | ------------------------------------------------------------------- |
| `kaizen apply`       | Main entry point. Applies desired state and renders dotfiles.       |
| `kaizen variant set` | Changes which variant implements a slot.                            |
| `kaizen bump`        | Runs configured update steps and re-captures changed managed files. |

---

## 6. Hook phases

```mermaid
sequenceDiagram
  participant User
  participant Kaizen
  participant Feature

  User->>Kaizen: install / init
  Kaizen->>Feature: post_install

  User->>Kaizen: apply / sync
  Kaizen->>Feature: post_apply

  User->>Kaizen: bump / update
  Kaizen->>Feature: post_update
```

Hook phase is part of the public API. Putting a hook in the wrong phase is a feature-authoring bug.

---

## 7. Open seams

```mermaid
flowchart TB
  Legacy["Legacy manual skhd configs own all shortcut bindings"]
  Catalog["Mnemonic catalog is reference-only today"]
  Chezmoi["Direct chezmoi apply can bypass Kaizen apply"]

  Legacy --> NeedOwnership["Gradually migrate key bindings to reference catalog"]
  Catalog --> NeedUsage["First consumer: Helix or skhd template helper"]
  Chezmoi --> NeedDocs["Document kaizen apply as the intended public entry point"]
```

These seams are intentionally visible because they are **not stable API yet**.
