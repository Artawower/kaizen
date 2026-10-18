# Helix configuration

Kaizen supports the official Helix release and the plugin-enabled `steel-event-system` fork.

Select the implementation in `~/.config/kaizen/config.toml`:

```toml
[helix]
variant = "standard"
```

or:

```toml
[helix]
variant = "steel"
```

The Steel variant uses Scheme as its primary configuration. `config.toml` stays empty so TOML keymaps do not conflict with Scheme keymaps. Official Helix ignores the Scheme files and therefore uses upstream defaults unless you configure its TOML keymap directly.

- `core.scm` owns Steel editor options.
- `bindings.scm` owns Steel keymaps.
- `languages.toml` owns language-server configuration.
- `init.scm` loads the Scheme configuration and Steel plugins.
- `appearance.scm` selects `my` or `my_light` from the system color scheme for Steel.
- `steel.scm` owns NREPL, Paredit, and Scheme language setup.
- `modeline.scm` configures Moka and Scopeline.
- `file-manager.scm` configures Forest.
- `helix.scm` exports commands to the Steel runtime.
- `bindings.scm` contains direct QWERTY keybindings; shortcut changes start in `config.example.toml` and are adapted into native configs.

Scheme keybindings include:

- `Space b b`: open the buffer picker.
- `Space ]` / `Space [`: go to the next / previous buffer.
- `Ctrl+j` / `Ctrl+k`: go to the next / previous diagnostic.
- `k` / `K`: go to the next / previous search match.
- `/`: open the search prompt, or search immediately for the current non-empty selection.
- `Space o f`: open or focus Forest.
- `Space o F`: close Forest when visible, otherwise open it. Forest captures keys while focused, so use `Escape` first or close it directly with `q`.

`languages.toml` mirrors the primary LSP setup from Emacs for Python, JavaScript, TypeScript, Vue, HTML, Go, and Rust. ESLint contributes only diagnostics and code actions, while Copilot contributes only completions. Angular starts only when the selected project root contains `angular.json`.

The `standard` variant installs the platform Helix package. The `steel` variant builds the fork, installs Forge packages, and links its runtime into `~/.config/helix/runtime`.

Changing variants does not remove the previous installation. When switching from `steel` to `standard`, remove the old `~/.cargo/bin/hx` if it still takes precedence over the platform binary.
