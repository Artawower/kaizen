# Architecture

Kaizen combines Python 3.11+, native package managers, mise, and chezmoi.
There is no build step and no third-party Python dependency for the orchestrator.

## Configuration

Committed defaults are in `dotfiles/.chezmoidata.toml`. User overrides are in
`~/.config/kaizen/config.toml`. Dictionaries merge recursively; scalar values
and lists replace defaults. Optional `~/.config/kaizen/dependencies.toml` adds
native packages and mise tools without editing feature manifests.

Before sync, Kaizen prepares the ignored `dotfiles/.chezmoidata/99-user.toml`.
For the current schema this is a symlink to the user config. Legacy schemas
are normalized into a generated TOML snapshot, refreshed on the next sync.
Chezmoi reads defaults and this overlay when rendering application configs.

## Features

Enabled features come from `[features]`. Their declarations live under
`features/<name>/`; variants add declarations under `variants/<variant>/`.
Package declarations are additive. Mise tools merge in feature order, then
variant overrides, then user dependencies. The resulting `~/.config/mise.toml`
is generated and should not be edited as a source of truth.

## Commands

- `install`: validate inputs, install native packages, generate mise config,
  install tools, then run enabled integrations with the `sync` action.
- `sync`: prepare the chezmoi overlay, perform installation, then force-apply
  dotfiles from the source tree.
- `update`: upgrade native packages globally, upgrade installed mise tools,
  then run enabled integrations with the `update` action.
- `bump`: development-only interactive mise upgrade and version capture.
- `capture`: development-only capture of known mutable Pi settings.
- `self-update`: fast-forward a clean managed installation; does not sync.
- `status`, `docs`, and `help`: inspect configuration and installation paths.

Native command failures stop the workflow. Required executables must be
available; Linux users install mise and chezmoi separately. Homebrew can be
bootstrapped interactively when needed on macOS.

Disabling a feature does not uninstall its packages or remove previously
applied files. Ignore rules control which files a subsequent apply manages;
there is no general automatic uninstall or rollback mechanism. The package,
file, and hook boundaries are still deliberately explicit, not a plugin DSL.

## Installation

`install.sh` reuses Python 3.11+ or bootstraps isolated Python through uv.
Managed installations use `~/.local/share/kaizen`; development installations
use `KAIZEN_SOURCE_DIR`. The wrapper at `~/.local/bin/kaizen` selects the
source and interpreter. Installer reruns and `self-update` are different
paths; the latter requires a clean checkout and an attached branch.

## Tests

`just test` runs the shell-based regression suites. Python checks are embedded
in those suites to avoid adding a separate application package or test runner.
Optional application validators run only when their executable is available.
DevCache tests exercise the current rootless implementation without real
storage devices, root privileges, or systemd installation.
