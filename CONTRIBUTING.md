# Contributing to Kaizen

Kaizen is an experimental developer environment built around Python 3.11+,
chezmoi, mise, and native package managers. Alternative editors, shells, and
window managers are welcome; changes should keep the main workflow small.

## Development setup

Install Python 3.11+, chezmoi, mise, and just. From the checkout:

```bash
KAIZEN_SOURCE_DIR="$PWD" sh install.sh
python3 kaizen.py status
just test
```

The installer links the wrapper to this checkout. It can offer to run a full
sync interactively; decline that prompt when only preparing development.
Tests use temporary directories and mocked commands rather than installing
packages or applying your real dotfiles.

## Layout and feature changes

- `kaizen.py` is the orchestrator.
- `features/<name>/packages.toml` declares native packages.
- Optional `mise.toml` declares runtime tools under `[tools]`.
- Optional `post_install.py` receives the OS identifier and `sync` or `update`.
- `features/<name>/variants/<variant>/` adds variant-specific declarations.
- `dotfiles/` is the chezmoi source tree.
- `config.example.toml` is the user configuration template.

See [the architecture](docs/architecture.md) and
[the feature format](docs/feature-format.org) for the current contracts.

## Daily workflow

Run `just test` before applying changes. For local application:

```bash
chezmoi --source "$PWD/dotfiles" diff
python3 kaizen.py sync
```

`sync` installs dependencies and applies dotfiles. Direct chezmoi commands
use the user overlay prepared by the last sync; they do not install packages.

In development mode, `kaizen bump` interactively upgrades mise tools and
captures their versions into feature-local `mise.toml` files. `kaizen capture`
re-adds known mutable Pi settings. Dependency lock files and generated caches
are not versioned. External skills remain upstream-managed and immutable.

## Version control

Use Jujutsu. Keep one logical change per revision and disable broken signing:

```bash
jj --config 'signing.behavior="drop"' status
jj --config 'signing.behavior="drop"' describe -m "chore: describe the actual change"
```

Do not publish changes without explicit approval.
