# Architecture

Kaizen combines Python 3.11+, native package managers, mise, and chezmoi.
There is no build step and no third-party Python dependency for the orchestrator.

## Configuration

Committed defaults are in `dotfiles/.chezmoidata.toml`. User overrides are in
`~/.config/kaizen/config.toml`. Dictionaries merge recursively; scalar values
and lists replace defaults. Optional `~/.config/kaizen/dependencies.toml` adds
native packages and mise tools without editing feature catalogs.

Before sync, Kaizen prepares the ignored `dotfiles/.chezmoidata/99-user.toml`.
It is a generated TOML snapshot of normalized user settings, refreshed on sync.
Chezmoi reads defaults and this overlay when rendering application configs;
direct chezmoi commands see the last snapshot, not subsequent user edits.

## Features

Kaizen reads `features/*.toml` category catalogs, ordered by filename and
then feature name. Each named section contains shared native `packages`, optional
`package_names` exceptions, flat manager-specific additions, inline mise `tools`,
optional metadata, and an explicit `post_install` path.
Only hooks and their assets live in `features/hooks/<name>/`. Feature names
are unique across catalogs; categories provide no inheritance or defaults.

Every feature applies unless archived or unsupported on the current OS;
there is no user feature enable list. `platforms` defaults to macOS and Linux.
An explicit list restricts the entire recipe. Optional `distributions` restricts
Linux distro IDs. The same filter selects package installs, generated mise
tools, and hooks. Dotfiles are
independent: chezmoi manages source files with general platform and generated-file
exclusions, not per-feature conditions. Unsupported apps may have unused configs
on an otherwise supported platform.

`archive = true` in a feature section skips it; omission means active.
The section, dependencies, and hook path stay in the category catalog. Move owned dotfiles to `.arhive/` to stop
managing them; the archive flag alone does not hide files from chezmoi.
Global package and mise upgrades still affect previously installed tools.
Installation does not select a running WM or activate its service. Multiple
WM packages and both Helix implementations can coexist; runtime selection is
separate from installation. WM-specific skhd profiles live inside their WM's
config directory; one shared `skhd/skhdrc` selects a profile through native
`.load`. The standard skhd service needs no custom arguments. Archive must
resolve references to the selected profile before moving it; unarchive does
not change this selector automatically.

Package declarations are additive. Before native installation, Kaizen resolves
explicit name aliases across active, eligible features and combines feature and
user packages into one ordered, deduplicated plan. Contradictory name mappings,
ambiguous aliases, wrong-manager aliases, or differing Homebrew flags reject the
plan before native commands run. This validates declarations, not repository
availability or arbitrary system package conflicts. See
[`feature-format.org`](feature-format.org) for the schema and alias rules.
Mise tools merge in discovery order, then user dependencies. Bump updates each applicable section's inline `tools` table,
preserving sibling sections, archived entries, and user-owned overrides. The resulting `~/.config/mise.toml` is generated and should
not be edited as a source of truth.

## Commands

- `install`: validate inputs, install native packages, generate mise config,
  install tools, then run applicable integrations with the `sync` action.
- `sync`: prepare the chezmoi overlay, perform installation, then apply
  dotfiles from the source tree with normal chezmoi conflict prompting.
- `update`: upgrade native packages globally, upgrade installed mise tools,
  then run applicable integrations with the `update` action.
- `bump`: development-only interactive mise upgrade and version capture.
- `capture`: development-only capture of known mutable Pi settings.
- `self-update`: fast-forward a clean managed installation; does not sync.
- `status`, `docs`, and `help`: inspect configuration and installation paths.

Native command failures stop the workflow. Required executables must be
available; Linux users install mise and chezmoi separately. Homebrew can be
bootstrapped interactively when needed on macOS.

Archiving a feature does not uninstall its packages or remove previously
applied files. Moving source files out stops future management, not deployment
already on disk. Conflicts during restore are resolved in the source tree
before applying; locally edited destination files retain chezmoi's normal
confirmation because sync and apply do not pass `--force`. There is no general
automatic uninstall or rollback mechanism. The package,
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
