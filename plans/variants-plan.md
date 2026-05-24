# Experimental features & variant slots — design plan

> Status: **draft / under discussion**. Living document. Author: kaizen@lead in
> collaboration with the user. Updated through chat iterations.

This document captures the design discussion around adding experimental /
swappable features to kaizen — using a window manager (yabai → aerospace →
komorebi → glazewm) as the driving example.

It is intentionally written as a chain so that future readers (and agents) see
**why** v2 supersedes v1 and not just the final answer.

---

## 1. Problem statement

Today kaizen is tightly coupled to the tools the author/community picked:

- yabai is hard-wired in `dotfiles/dot_config/nix/modules/features/tiling.darwin.nix`
  together with `skhd`, `borders`, `aerospace` — all glued into a single
  "tiling" feature with no way to swap any one of them.
- The Rust core's `FeatureSelection { enabled: bool, disabled_atoms: Vec<String> }`
  has no concept of "one of N", "role", "variant" or "provides". Features are
  boolean.
- The closest existing precedent for "one of N" is `layout = "colemak" | "qwerty"`
  in `.chezmoidata.toml`, switched by a standalone `scripts/layout` shell
  script that bypasses the CLI entirely. It works, but it is ad-hoc and lives
  outside the core model.
- dotfile overlays for variants are handled via `.chezmoiignore.tmpl` —
  already a working pattern in the repo.
- `TargetOs::Windows` does not exist in core; Windows is `Unknown`. So any
  cross-OS variant story is mac-first today, Windows-deferred.

### Goal

Build a **seamless, extensible mechanism** for:

1. **Trying experimental features** without touching the stable base.
2. **Swapping any existing dependency** (nix packages and/or chezmoi dotfiles)
   for an alternative implementation.
3. Keeping the mechanism **OS-aware** (each alternative declares which
   platforms it supports).
4. Exposing it through **core API** first, with CLI as one consumer (TUI/GUI
   later possible).

### Non-goals (MVP)

- Windows host support (no `TargetOs::Windows` yet).
- Patching other features' files (e.g. an experiment that mutates
  `dot_config/helix/config.toml`). This is patch mechanics, not variation —
  out of scope.
- Migrating the existing `layout = colemak|qwerty` to the new mechanism.
  Possible follow-up; not required for MVP.

---

## 2. Approach v1 — Experiments as an isolated overlay (rejected)

### Sketch

A top-level `experiments/` directory parallel to `dotfiles/`. Each experiment
is a self-contained package:

```
experiments/komorebi-wm/
├── experiment.toml      # manifest
├── nix/                 # nix modules added when the experiment is enabled
└── dotfiles/            # chezmoi overlay, same layout as main dotfiles
```

Manifest declares what to add, what to disable in the stable base, conflicts
with other experiments, and supported platforms:

```toml
id = "komorebi-wm"
status = "alpha"
platforms = ["darwin"]
[replaces]
features      = ["yabai"]
dotfile_paths = ["dot_config/yabai/", "dot_config/skhd/"]
[requires]
features  = ["sketchybar"]
conflicts = ["aerospace-wm"]
```

Activation via `kaizen --experimental` / `kaizen experiment enable <id>`,
stored as `[experiments] enabled = [...]` in `data.toml`.

Substitution mechanics:

- **nix**: `feature-loader.nix` loads experiment modules, force-disables
  features listed in `replaces.features`.
- **chezmoi**: core builds an _effective source_ in a temp dir before each
  apply — copy main dotfiles, layer experiment dotfiles on top, append
  `replaces.dotfile_paths` to `.chezmoiignore`, then `chezmoi apply --source <temp>`.

### Why rejected

**Two structural problems** surfaced in the next review round:

1. **Rebuilding the chezmoi source on every apply is overkill.** The repo
   already separates each WM into its own folder (`dot_config/yabai/`,
   `dot_config/aerospace/`) and `.chezmoiignore.tmpl` already knows how to
   branch on `data.toml` (the `layout` precedent). Building a temporary
   merged source for every `apply` reinvents what `.chezmoiignore` does
   declaratively — extra moving parts, extra failure modes, audit-trail
   problems on cleanup.

2. **`conflicts: [...]` introduces backward coupling.** Each new experiment
   has to be aware of every other experiment it is mutually exclusive with.
   Adding a third WM experiment means editing the manifests of the first
   two. That does not scale.

3. **Asymmetry between experimental and stable.** v1 splits the world into
   "stable lives in `dotfiles/features/`, experimental lives in
   `experiments/`". Graduating an experiment to stable becomes a multi-file
   migration. Demoting a stable feature back to experimental — same. The
   boundary should be a _flag_, not a _directory_.

These three points argued for a different abstraction.

---

## 3. Approach v2 — Slots & Variants (current proposal)

### Core idea

Lift variation **into the feature itself**. A feature may expose one or more
**slots** (extension points). Each slot has one or more **variants** (concrete
implementations). Exactly one variant is active per slot at any time.

| Concept     | Meaning                                                                                                   |
| ----------- | --------------------------------------------------------------------------------------------------------- |
| `Feature`   | as today (`tiling`, `helix`, …). May expose 0..N slots.                                                   |
| `Slot`      | a named extension point on a feature, e.g. `tiling.wm`.                                                   |
| `Variant`   | a concrete implementation of a slot. Owns its nix modules and its dotfile paths.                          |
| `Stability` | a field on a variant: `stable` or `experimental`. The **only** thing that makes a variant "experimental". |

### Invariants

- Exactly one variant is active per slot. A slot has a per-platform default
  (the only `stable` variant on that platform, by convention).
- Variants are **OS-scoped** — each variant declares `platforms = [...]`.
- Variants are **self-contained**: each variant owns its nix modules and its
  dotfile path roots. No variant references another by id.
- Mutual exclusion is **structural**: one slot, one variant. No `conflicts`
  list needed.

### Consequences

- ❌ No `conflicts` field — backward coupling gone.
- ❌ No temp-dir overlay — substitution happens by toggling `.chezmoiignore`
  entries, the same mechanism `layout` already uses.
- ❌ No separate `experiments/` tree — experimental is a _property_ of a
  variant, not a directory.
- ✅ Graduation `experimental → stable` is a one-line patch:
  `stability = "stable"` in the variant manifest.
- ✅ Cross-OS variation is first-class — slot picks the right variant for the
  current OS automatically.
- ✅ Stand-alone experiments (no existing slot to plug into) are just new
  features with a single variant whose `stability = "experimental"`. Same
  model, special case.

### On-disk layout

```
features/
├── tiling/
│   ├── feature.toml
│   │       slots = [{ id = "wm", required = true }]
│   └── variants/
│       ├── yabai/
│       │   ├── variant.toml      # slot = "wm", platforms = ["darwin"], stability = "stable", default = true
│       │   └── module.darwin.nix
│       ├── aerospace/
│       │   ├── variant.toml      # slot = "wm", platforms = ["darwin"], stability = "experimental"
│       │   └── module.darwin.nix
│       └── komorebi/
│           ├── variant.toml      # slot = "wm", platforms = ["windows"], stability = "experimental"
│           └── module.windows.nix
└── helix/
    └── feature.toml              # no slots — feature unchanged
```

Dotfiles stay where they are; each variant declares ownership in its manifest.

### Variant manifest

```toml
id        = "aerospace"
slot      = "tiling.wm"
title     = "AeroSpace (i3-like tiling for macOS)"
stability = "experimental"     # stable | experimental
platforms = ["darwin"]
default   = false              # true => default for the slot on this platform

[provides]
nix_modules   = ["module.darwin.nix"]
dotfile_paths = ["dot_config/aerospace/"]   # owned by this variant
brew_casks    = ["nikitabobko/tap/aerospace"]

[requires]                      # optional soft dependencies, not conflicts
features = ["sketchybar"]
```

A variant **only describes itself** and the slot it plugs into. It never
references any other variant.

### Substitution mechanics

**Nix dependencies.** `feature-loader.nix` reads `data.toml`, picks the active
variant per slot, loads only that variant's `nix_modules`. Other variants
contribute nothing.

**Chezmoi dotfiles.** Core computes the union of `dotfile_paths` for every
_inactive_ variant of every slot and writes that list into `.chezmoidata.toml`.
A single `.chezmoiignore.tmpl` ranges over the list and ignores those paths.
This is the same machinery as `layout = colemak|qwerty` today, just driven
declaratively by variant manifests instead of hand-rolled templates.

No temp dirs. No copying. No overlay.

**Platform filter.** Variants declare `platforms`. Slot resolution on a given
host only considers variants whose `platforms` include the current OS.
A slot with no eligible variants on the current OS is hidden (the parent
feature behaves as it does today — disabled if there is nothing to plug in).

### Selection storage

```toml
# ~/.config/kaizen/data.toml
[variants]
"tiling.wm" = "aerospace"
```

Persisted through the existing `merge_kaizen_data_with` — no migration.

### Cross-feature substitution

Out of scope. A variant cannot rewrite files owned by another feature
(e.g. an experiment that mutates `dot_config/helix/config.toml`). Use existing
`.tmpl` templating with `data.toml` branches for that — it is a different
problem (patching) with different invariants (conflict-prone, ordered).

---

## 4. UX

### `kaizen configure`

```
[x] Tiling window manager
    Implementation:  ( ) yabai       (default, stable)
                     ( ) aerospace   (experimental — needs --experimental)
```

Without `--experimental` the slot picker is hidden when only one stable
variant exists on this OS. With `--experimental` all eligible variants are
listed; an indicator marks experimental ones.

### CLI (proposed)

- `kaizen variant list [--slot tiling.wm] [--experimental]`
- `kaizen variant show <slot> <variant>`
- `kaizen variant set <slot> <variant>` — write `data.toml`, prompt to `sync`
- `kaizen variant reset <slot>` — back to default

### `kaizen doctor`

Verifies: active variant exists, supports current OS, its `requires.features`
are enabled.

---

## 5. What changes — by layer

### kaizen-core (Rust)

- New models: `Slot`, `VariantManifest`.
- `FeatureFile` gains optional `slots: Vec<Slot>`.
- `FeatureStore` also discovers `features/<name>/variants/*/variant.toml`.
- `Config` gains `variants: BTreeMap<String, String>` (slot fqn → variant id).
- New module `variants.rs` with `VariantResolver` — public API: list slots,
  filter by platform / stability, validate, resolve defaults, produce an
  effective plan (which nix modules to load, which dotfile paths to ignore).
- `merge_kaizen_data_with` handles the new `[variants]` section transparently.
- Core also writes computed `inactive_dotfile_paths` to `.chezmoidata.toml`
  so the chezmoi template can range over it.

### nix dotfiles

- `feature-loader.nix` learns about variants — only loads `nix_modules` of
  the active variant per slot.
- `tiling.darwin.nix` is split:
  - yabai bits → `features/tiling/variants/yabai/module.darwin.nix`
  - aerospace bits → `features/tiling/variants/aerospace/module.darwin.nix`
  - shared bits (skhd, borders) stay in `features/tiling/feature.toml`.

### CLI

- `kaizen variant …` subcommands.
- `kaizen configure` learns to walk slots when `--experimental` is set, or
  when a slot has multiple stable variants.
- `kaizen doctor` checks.

### docs

- This file (`plans/variants-plan.md`).
- `docs/feature-format.org` extended with a "Slots & Variants" section once
  the design is locked.

### What does **not** change

- `Feature.enabled: bool` stays. Slots are orthogonal to feature enablement.
- The `.chezmoidata.toml` + `.tmpl` mechanism stays — slots feed into it.
- Existing slot-less features are untouched.

---

## 6. Comparison v1 vs v2

|                            | v1 (experiments overlay)               | v2 (slots & variants)                       |
| -------------------------- | -------------------------------------- | ------------------------------------------- |
| Where variants live        | Separate `experiments/` tree           | Inside `features/<name>/variants/`          |
| Mutual exclusion           | Explicit `conflicts: [...]`            | Structural (one slot = one variant)         |
| Dotfile substitution       | Temp-dir overlay built per apply       | `.chezmoiignore` (same as `layout`)         |
| Graduation to stable       | Move files between trees               | One field flip (`stability = "stable"`)     |
| Platform awareness         | Manifest field                         | Manifest field + per-OS variants            |
| Cross-feature file patches | Declarative (`replaces.dotfile_paths`) | Out of scope (use `.tmpl`)                  |
| Code complexity            | Medium                                 | Low                                         |
| Reuses existing patterns   | Partially                              | Fully (layout pattern, `.chezmoidata.toml`) |

---

## 7. Open questions (to be resolved before implementation)

1. **Terminology**: `slot` / `variant`. Acceptable, or rename? (`role` /
   `implementation` is the obvious alternative.)
2. **Splitting `tiling.darwin.nix`**: OK to touch the stable base in the
   very first commit? Or grow the variants tree first, leave the old file in
   place, then cut over in a later commit?
3. **`requires.features`**: hard fail in `variant set` or soft warning in
   `doctor`?
4. **MVP CLI scope**: ship only `configure --experimental`, defer
   `kaizen variant set/list/show`? Or ship them together because they share
   the same `VariantResolver`?
5. **Dummy variant for E2E**: do we add a trivial no-op variant for a fake
   feature (just to exercise the plumbing in tests), or use `aerospace` as
   the test subject from day one?

---

## 8. Roadmap (skeleton, v2 — to be refined)

Atomic jj revisions, each delegated to `kaizen@coder` separately and reviewed
before the next is started.

| #   | Step                                                                                            | Layer        |
| --- | ----------------------------------------------------------------------------------------------- | ------------ |
| 1   | New models in core: `Slot`, `VariantManifest` + serde + unit tests                              | core         |
| 2   | `FeatureStore` discovers variants; `VariantResolver` (filter, defaults, validation) + tests     | core         |
| 3   | `Config.variants` + read/write `[variants]` in `data.toml` via `merge_kaizen_data_with` + tests | core         |
| 4   | Effective plan: list of inactive `dotfile_paths` written to `.chezmoidata.toml`                 | core         |
| 5   | `.chezmoiignore.tmpl` ranges over inactive paths                                                | dotfiles     |
| 6   | `feature-loader.nix` learns about variants                                                      | nix dotfiles |
| 7   | Split `tiling.darwin.nix` → `features/tiling/variants/{yabai,aerospace}/…`                      | nix dotfiles |
| 8   | CLI: `kaizen variant list/show/set/reset`                                                       | cli          |
| 9   | CLI: `configure --experimental` walks slots                                                     | cli          |
| 10  | `kaizen doctor` checks                                                                          | cli          |
| 11  | E2E test: enable variant → apply → verify $HOME state → reset → apply → rollback                | tests        |
| 12  | Docs: extend `feature-format.org` + this file → "Approved"                                      | docs         |

Steps 1–8 are MVP. 9–12 are polish.

---

## 9. Conversation log (running notes)

- **Round 1.** Lead proposed three approaches: A (data.toml + templates only),
  B (full role model in core), C (hybrid — metadata in nix registry, thin
  resolver in core). User answered: WM choice not important, mechanism must
  swap both deps and dotfiles, suggested _separate experiments folder_
  triggered by `--experimental`, asked to design.
- **Round 2.** Lead proposed v1 (experiments overlay) with temp-dir overlay
  and `conflicts`. User pushed back on rewriting all dotfiles and on
  `conflicts` (backward coupling, would force every experiment to know about
  every other). Asked: can we build this on top of a _universal variation
  mechanism_? How does platform-specific play in?
- **Round 3.** Lead proposed v2 (slots & variants). Variation lifted into the
  feature itself; experimental is just a `stability` flag; mutual exclusion
  is structural; dotfile substitution uses the existing `.chezmoiignore`
  mechanism rather than overlay. Document captures this state.
- **Round 4.** TBD — user requested this plan be recorded for further
  discussion.

---

## 10. MVP delivered

Revision `feat(variants): introduce slot/variant model with aerospace as experimental tiling.wm`
implements steps 1–8 of the roadmap.

### What was built

| Layer                                                        | What changed                                                                                                                                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `kaizen-core/src/variants.rs`                                | New module: `Slot`, `VariantManifest`, `Stability`, `VariantResolver`, `discover_variants`. Unit tests: list slots, filter by OS/stability, default resolution, inactive dotfile paths.          |
| `kaizen-core/src/config.rs`                                  | `UserConfig.variants: BTreeMap<String,String>` (slot fqn → variant id).                                                                                                                          |
| `kaizen-core/src/plan.rs`                                    | `ConfigPlan.variants` propagated through workflow.                                                                                                                                               |
| `kaizen-core/src/chezmoi.rs`                                 | `merge_kaizen_data_with` handles `[variants]` section with preserve-unknown semantics. +3 tests.                                                                                                 |
| `kaizen-core/src/backends/common.rs`                         | `write_variant_data_to_chezmoi` writes active variant selections back to `.chezmoidata.toml` (e.g. `tilingWm = "aerospace"`). `slot_to_chezmoi_key` converts `tiling.wm` → `tilingWm`. +3 tests. |
| `kaizen-cli/src/commands/variant.rs`                         | New CLI subcommand: `kaizen variant list/show/set/reset`.                                                                                                                                        |
| `kaizen-cli/src/main.rs`                                     | `Command::Variant` + `VariantAction` enum registered.                                                                                                                                            |
| `features/tiling/`                                           | `feature.toml` declares `wm` slot. `variants/yabai/variant.toml` (stable, default). `variants/aerospace/variant.toml` (experimental). Nix modules per variant.                                   |
| `dotfiles/.chezmoiignore.tmpl`                               | Branches on `tilingWm`: deploys only the active variant's dotfiles.                                                                                                                              |
| `dotfiles/.chezmoidata.toml`                                 | `tilingWm = "yabai"` default for chezmoi-only users.                                                                                                                                             |
| `dotfiles/dot_config/nix/modules/features/tiling.darwin.nix` | Branches on `user.tilingWm` for brew casks/formulas/taps/activation.                                                                                                                             |
| `dotfiles/dot_config/nix/user.nix.tmpl`                      | Exposes `tilingWm` to Nix evaluation.                                                                                                                                                            |
| `dotfiles/dot_config/aerospace/aerospace.toml`               | Minimal working aerospace config.                                                                                                                                                                |
| `features/tiling/variants/glazewm/variant.toml`              | Third variant: GlazeWM (i3-like, cross-platform, experimental). Installs via `glzr-io/tap` cask alongside Zebar status bar.                                                                      |
| `features/tiling/variants/glazewm/module.darwin.nix`         | Homebrew tap `glzr-io/tap`, casks `glazewm` + `zebar`. No brews.                                                                                                                                 |
| `dotfiles/dot_config/glazewm/config.yaml`                    | Full GlazeWM config adapted from yabai+skhd: 10 named workspaces, app rules, Colemak keybindings (h=left, n=down, e=up, i=right), purple focus borders.                                          |

### End-to-end flow

```
kaizen variant list                             ← shows yabai (stable, active), aerospace (experimental)
kaizen variant set tiling.wm aerospace          ← fails: experimental, missing --experimental
kaizen variant set tiling.wm aerospace --experimental  ← writes data.toml [variants] + .chezmoidata.toml
kaizen sync                                     ← chezmoi apply uses tilingWm=aerospace:
                                                   • deploys dot_config/aerospace/
                                                   • ignores dot_config/yabai/, dot_config/skhd/
                                                   • darwin.nix installs aerospace cask, not yabai
```

### Remaining steps (post-MVP)

| #   | Step                                          | Notes                                                          |
| --- | --------------------------------------------- | -------------------------------------------------------------- |
| 9   | `configure --experimental` walks slots        | wizard UX                                                      |
| 10  | `kaizen doctor` checks for variants           | validate active variant exists, OS matches, requires satisfied |
| 11  | E2E test                                      | needs macOS runner; Darwin-only feature                        |
| 12  | `feature-format.org` Slots & Variants section | user documentation                                             |
| 13  | Contributions / drop-fragment mechanism       | variant adds to another feature's config                       |
| 14  | Migrate `layout = colemak\|qwerty` to slots   | uniformity                                                     |
| 15  | Windows support                               | `TargetOs::Windows` deferred                                   |

> Known limitation: variant nix-modules duplicated between `tiling.darwin.nix` (active) and `features/tiling/variants/*/module.darwin.nix` (declared but not loaded). Will be unified when `feature-loader.nix` learns to consume variants from `features/` tree (step #16, post-MVP).

> Status: **MVP implemented**. Pending review.

## 11. Wizard integration delivered

### What was added

- **`WizardTree` / `WizardNode`** — tree model in core. `WizardNode::Slot` contains `Vec<WizardNode::VariantOption>` children sorted stable-first then lexicographic. Slot only appears when it has **≥ 2** candidates after OS+stability filter.
- **`VariantResolver::build_wizard_tree(os, include_experimental, current_selections)`** — pure headless method that builds the tree. UI does zero filtering.
- **`KaizenEngine::build_wizard_tree(include_experimental)`** — single public entry point: detects OS, discovers variants, reads current selections, delegates to resolver.
- **`KaizenEngine::current_variant_selections()`** — reads `[variants]` from `data.toml`.
- **`KaizenEngine::apply_variant_selections(selections)`** — replaces `[variants]` block entirely (preserves all other keys).
- **`write_variant_selections(path, selections, fs)`** in core — full-replace semantics (not merge-append).
- **`selector::pick_tree(prompt, init_experimental, tree_builder)`** — tree TUI with fold/unfold (`Tab`), radio select (`Space`), experimental toggle (`E`), `j/k` navigation, `Enter` confirm, `q`/`Esc` cancel.
- **Pure state helpers** (`flatten_visible`, `apply_selection`, `is_changed`, `toggle_fold`, `initial_selections_from_tree`) — all unit-tested without TUI.
- **`kaizen configure --experimental`** flag — initial value for `E` toggle.
- **Variant step in wizard** — placed between `pick_features` and `pick_layout`; silently skipped when initial tree is empty.
- **`kaizen variant list` / `show` removed** — overlap with wizard. `set` / `reset` retained for CI/scripting.

### UX decisions

- **Tree model**: slots are foldable headers, variants are radio children. All unfolded by default.
- **`E` toggle**: runtime switch between stable-only and all variants. Rebuilds tree on each toggle, preserves fold state and selections.
- **`--experimental` = initial E state**: `kaizen configure` starts with E=off (stable only), `kaizen configure --experimental` starts with E=on.
- **Slot visibility rule**: slot hidden when `< 2` candidates remain after filtering. Recalculated on each E-toggle.
- **Silent skip**: if initial tree (with `--experimental` preset) is empty → `pick_tree` not called.
- **No-op on unchanged selection**: `Enter` without mutation → `data.toml` not written.
- **Full replace semantics**: `apply_variant_selections` replaces entire `[variants]` block.

### Post-MVP backlog

- Scrolling when slots grow beyond terminal height.
- `kaizen doctor` checks: active variant exists, OS matches, required features enabled.
- E2E wizard test (needs interactive runner).
- `feature-loader.nix` consuming variants from `features/` tree (step #16) — eliminates dual-store.
