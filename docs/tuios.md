# TUIOS migration

Targets TUIOS 0.10.1. Herdr workspace → TUIOS session, tab → workspace,
pane → window. The [shortcut table](shortcuts.md#terminal-multiplexer) keeps
those three layers separate.

## Install and apply

`kaizen sync` installs the pinned TUIOS release through mise. Herdr and its
configuration remain installed for existing integrations and rollback; this
migration does not move or terminate running herdr sessions. Ghostty still
starts Nushell; run `tuios` there to use the new multiplexer.

The shared configuration lives at `~/.config/tuios/shared.toml`. Both native
entry points include it:

- macOS: `~/Library/Application Support/tuios/config.toml`
- Linux: `~/.config/tuios/config.toml`

The shell path and theme preferences are templated; keybindings remain literal.
Chezmoi resolves `[terminal].shell` to an
absolute executable path; TUIOS 0.10.1 expects `appearance.preferred_shell`,
not `daemon.preferred_shell`, and does not resolve a bare name on Unix.
Existing Nushell configuration supplies Carapace completions.

New sessions start tiled in BSP and terminal mode, with one pane. BSP replaces
the captured master-stack startup layout because explicit right/below splits
and `ArrangePanes tiled` need it. The initially hidden sidebar, other chrome
settings and desktop agent notifications are retained.
Agent detection is enabled; herdr's exact agent-label-on-border setting has
no direct TUIOS option. Kitty graphics needs no herdr experimental flag.

## Light and dark themes

`[ui.theme]` in `config.example.toml` defines the preferences; committed
chezmoi defaults match them and user overrides take precedence. `dark` maps
to TUIOS `appearance.theme`, and `light` to `appearance.theme_light` when
`auto_switch = true`. The defaults are Catppuccin Mocha and Latte, not Frappe.
Hyphenated preference names map to TUIOS underscore-separated theme IDs.

TUIOS follows the local terminal background and light/dark change notifications
(mode 2031), including after startup. Ghostty already switches light/dark
with the system. This needs no watcher, external command or TUIOS restart.
`auto_switch = false` leaves the dark theme fixed. An explicit `tuios --theme`
argument takes precedence over the pair and disables automatic selection.
Terminals that do not report their background/scheme cannot guarantee live
switching; the dark theme is the initial fallback. Remote clients have
separate engine limitations and are not covered by this local-terminal setup.

After applying, run:

```sh
tuios config files
tuios keybinds doctor
```

Key changes reload live. Startup settings affect new sessions, not existing
layouts. In-app edits can write the included shared file or add local overrides
to the native entry point; capture deliberate changes before applying again.

## Keyboard behavior

Bindings use logical characters, including on Colemak, not QWERTY key positions.
Russian aliases are explicit for configurable command/navigation tables,
including Shift and modified keys. Input and searches are not transliterated.
Ghostty already clears its default shortcuts and forwards unbound Command keys
through the Kitty keyboard protocol. Other terminals may intercept them.

TUIOS accepts only one `leader_key`. `Ctrl+и` reaches `Ctrl+b` through its
Kitty base-key fallback (the B position is shared by Colemak and QWERTY),
not through a second configured leader. Without Kitty base-key reporting,
use Latin input for the prefix. `keyboard_layout = "other"` and
`option_glyphs = "type"` avoid interpreting composed text as US Option keys;
Ghostty's existing `macos-option-as-alt = true` sends actual Alt chords.

The palette moves from TUIOS's default `Ctrl+p` to `Ctrl+Shift+p`; the default
`Alt+Space` launcher is unbound. This preserves shell/editor input.
`Ctrl+Alt+h/j/k/l` is not intercepted by this configuration.
Conflicting prefix defaults are explicitly unbound: for example, `prefix q`
detaches rather than killing a session, `prefix v` splits rather than opening
review, and `prefix 1..9` selects tabs rather than panes. Other TUIOS features
remain available through the palette and its native menus.

## Differences that cannot be copied exactly

- Herdr's persistent resize mode has no native equivalent. `prefix r` opens
  the layout menu, where `h/j/k/l` performs one five-cell resize. Repeat the
  sequence for another step, or use `prefix Alt+h/j/k/l`, which supports
  TUIOS's timed prefix repeat. Layout loading moves to `prefix r p`;
  pane renaming remains available through `prefix t r`.
- The herdr tiled/balance plugin is replaced by `ArrangePanes tiled` on
  `prefix Alt+5` and native split equalization on `prefix Shift+e`. Grid
  arrangement requires BSP; it reports an error in other layouts.
- Herdr's `Alt+p` / `prefix Shift+o` worktree picker has no faithful native
  equivalent. These keys are not rebound. TUIOS's rail can create Git
  worktrees, but that is not a Jujutsu workspace picker and must not replace
  it silently. Use the session picker for already opened projects.
- TUIOS's fixed copy-mode/help/confirmation keys use its US-position fallback.
  They cannot implement all Colemak/Russian aliases from the intent file.
  Use Latin input there. The configurable lists, sidebar, Inbox and mail do
  have explicit aliases.
- Numbered workspaces are TUIOS slots, not an unlimited herdr tab list.
- TUIOS's herdr socket compatibility does not redirect a literal `herdr`
  executable on `PATH`. Existing herdr-specific scripts are not migrated by
  this keyboard configuration; integrations must use the compatibility
  socket and `$HERDR_BIN_PATH`, or gain a native TUIOS backend.

No terminal keyboard events or live-session operations are exercised by
`tests/tuios-config.sh`; it renders isolated configs and checks the installed
TUIOS binding registry and doctor report. Verify actual Latin/Russian input
in Ghostty after applying, especially Command chords and the Russian prefix.

## Upstream references

- [Configuration](https://tuios.dev/docs/configuration)
- [Keybindings](https://tuios.dev/docs/keybindings)
- [Split configuration](https://tuios.dev/docs/config-files)
- [Herdr compatibility](https://tuios.dev/docs/herdr-compatibility)
- [Worktrees](https://tuios.dev/docs/worktrees)
- [CLI reference](https://tuios.dev/docs/cli-reference)
