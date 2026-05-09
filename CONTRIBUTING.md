# Contributing to Kaizen

## Repository layout

```
kaizen/
├── .chezmoiroot               ← tells chezmoi to use dotfiles/ as source root
├── crates/                    ← Rust source (kaizen CLI + core library)
├── docs/                      ← architecture and feature-format docs
└── dotfiles/                  ← chezmoi source root (applied to ~/)
    ├── .chezmoiignore         ← excludes kaizen/ from being applied to $HOME
    ├── kaizen/
    │   ├── manifest.toml      ← schema version
    │   └── features/          ← curated workflow features (single source of truth)
    └── dot_config/            ← ~/.config/* dotfiles
```

## Dev setup (one-time)

### 1. Install Rust toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### 2. Install required tools

```bash
# chezmoi — dotfiles manager
curl -fsSL https://chezmoi.io/get | sh

# mise — runtime/tool version manager
curl https://mise.run | sh
```

### 3. Point chezmoi at the local repo

This lets `kaizen sync` (and the planned `kaizen bump`) use your local `dotfiles/`
instead of cloning from GitHub:

```bash
cd /path/to/kaizen
chezmoi init file://$PWD
```

After this, `chezmoi source-path` returns `<repo>/dotfiles/`.
`kaizen` will resolve features from `dotfiles/kaizen/features/` automatically.

## Daily dev workflow

### Adding or editing a feature

Features live in `dotfiles/kaizen/features/`. Edit directly:

```bash
# add a new feature
$EDITOR dotfiles/kaizen/features/docker.toml

# preview what kaizen would do
kaizen sync --dry-run

# apply locally
kaizen sync
```

No copying required — `dotfiles/kaizen/features/` is the single source of truth.

### Editing dotfiles (`dot_config/`)

```bash
# preview changes
chezmoi --source ./dotfiles diff

# apply locally without publishing
chezmoi --source ./dotfiles apply

# or after chezmoi init (step 3 above), just:
kaizen apply
```

### Bumping dependency versions

`kaizen bump` upgrades mise tools, updates nix flake inputs, and re-adds lock
files back into the chezmoi source. After the dev setup above it writes
directly into `./dotfiles/`:

```bash
kaizen bump           # bump everything: nix flake inputs + mise tools
kaizen bump --nix     # only update nix flake inputs
kaizen bump --mise    # only bump mise tool versions
kaizen bump --dry-run # preview what would run
```

Then commit the updated lock files:

```bash
jj new -m "chore: bump dependencies"
# lock files are already updated in dotfiles/ by bump
```

### Running tests

```bash
cargo test
cargo clippy -- -D warnings
```

### Building locally

```bash
cargo build
# run the dev binary from repo root — features auto-resolved from dotfiles/kaizen/features/
./target/debug/kaizen sync --dry-run
```

## Feature dir resolution order

When `kaizen` starts it resolves the features directory in this order:

| Priority | Source                                                                     |
| -------- | -------------------------------------------------------------------------- |
| 1        | `--features-dir` flag or `KAIZEN_FEATURES_DIR` env var                     |
| 2        | Active chezmoi source: `<chezmoi source-path>/kaizen/features`             |
| 3        | Monorepo dev layout: `./dotfiles/kaizen/features` (running from repo root) |
| 4        | Fallback: `./features`                                                     |

This means running `kaizen` from the repo root works out of the box during
development without any extra flags.

## Proposing changes

Kaizen is opinionated by design. Before adding a tool, shortcut, or feature:

- explain what problem it solves;
- explain what it replaces or improves;
- prefer open-source tools;
- prefer changes that benefit many users, not a single private setup.

Open a discussion or issue before large changes.
