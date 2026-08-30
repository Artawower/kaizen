# Helix Steel configuration

Kaizen installs the `steel-event-system` branch of `mattwparas/helix` and links its runtime into `~/.config/helix/runtime`.

- `init.scm` composes the configuration modules.
- `core.scm` owns Helix editor options.
- `appearance.scm` selects `my` or `my_light` from the system color scheme at startup.
- `bindings.scm` owns shared normal, insert, and select keymaps.
- `tools.scm` owns terminal, Yazi, and Scooter actions.
- `vcs.scm` owns jjui, gitu, lazygit, gitui, and history actions.
- `steel.scm` owns NREPL, Paredit, and Scheme language setup.
- `helix.scm` exports commands to the editor runtime.
- `kaizen.scm` is generated from the shared Kaizen shortcut registry.
- `languages.toml` remains the declarative language-server configuration.
- `config.toml` is intentionally empty so configuration is not duplicated outside Steel.

Run `just sync` to update the fork, Steel tools, Forge packages, runtime, and generated configuration.
