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

`config.toml` is the shared configuration for both variants. Official Helix reads it and ignores the Scheme files. The Steel variant reads the same TOML configuration, then loads plugins and plugin-specific behavior from `init.scm`.

- `config.toml.tmpl` owns shared editor options and keymaps.
- `languages.toml` owns language-server configuration.
- `init.scm` loads Steel plugins and Scheme integrations.
- `appearance.scm` selects `my` or `my_light` from the system color scheme for Steel.
- `steel.scm` owns NREPL, Paredit, and Scheme language setup.
- `modeline.scm` configures Moka and Scopeline.
- `file-manager.scm` configures Forest.
- `helix.scm` exports commands to the Steel runtime.
- `kaizen.scm` is generated from the shared Kaizen shortcut registry.
- `core.scm.bak` and `bindings.scm.bak` preserve the previous Scheme configuration.

The `standard` variant installs the platform Helix package. The `steel` variant builds the fork, installs Forge packages, and links its runtime into `~/.config/helix/runtime`.

Changing variants does not remove the previous installation. When switching from `steel` to `standard`, remove the old `~/.cargo/bin/hx` if it still takes precedence over the platform binary.
