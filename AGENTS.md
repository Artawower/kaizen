# Kaizen — Agent Reference

Kaizen is a dotfiles and developer environment manager. No Nix, no Rust.
Stack: **Python 3.11+**, **chezmoi** (dotfiles), **mise** (runtimes), **brew/dnf/apt** (packages).

## Repository layout

```
features/<name>/
  packages.toml     # system packages per OS (required)
  mise.toml         # runtime tools via mise (optional)
  post_install.py   # runs after packages, receives OS name as argv[1] (optional)
  variants/<name>/
    packages.toml   # additional packages for this variant
    mise.toml       # additional runtime tools (optional)
    post_install.py # variant-specific setup (optional)

dotfiles/           # chezmoi source tree (dot_config/ → ~/.config/, etc.)
kaizen.py           # orchestrator — the only Python source file
config.example.toml # user config template
Justfile            # thin wrappers: sync, update, bump, capture, status, install
```

## Feature anatomy

`packages.toml`:

```toml
description = "..."
category = "dev"          # system | dev | editor | terminal | desktop | ai | ...

[macos]
taps = ["tap/name"]
brew = ["pkg-a", "pkg-b"]
cask = ["app-name"]

[macos.brew_args]         # per-package flags
"pkg-a" = ["--with-foo"]

[linux]
dnf = ["pkg-a"]           # Fedora/RHEL
apt = ["pkg-a"]           # Ubuntu/Debian
flatpak = ["com.app.Id"]
```

`mise.toml` — standard mise format, only `[tools]` section:

```toml
[tools]
go = "latest"
"npm:typescript" = "6.0.3"
"go:golang.org/x/tools/gopls" = "0.20.0"
```

`kaizen sync` generates `~/.config/mise.toml` by merging `mise.toml` from all enabled features.

## User config

`~/.config/kaizen/config.toml` (user edits this, not committed):

```toml
layout = "colemak"

[features]
core = true
go = false
tiling = true

[tiling]
variant = "yabai"

[kaizen.shortcuts]
"nav.down" = ["n"]
```

`dotfiles/.chezmoidata.toml` contains committed defaults. Kaizen deep-merges the user config over those defaults and generates the ignored `dotfiles/.chezmoidata/99-user.toml` symlink before applying chezmoi. Dictionaries merge recursively; lists and scalar values are replaced.

## Key commands

| Command | Effect |
| --- | --- |
| `just sync` | install packages → generate mise.toml → mise install → chezmoi apply |
| `just bump` | mise upgrade --interactive → capture new versions to feature mise.toml files |
| `just capture` | chezmoi re-add for known mutable paths (pi settings, mcp config) |
| `just update` | brew/dnf upgrade + mise upgrade |
| `just status` | show OS, config path, tool locations |

## VCS — jj (not git)

This repo uses **jj**. Never use `git commit` or `git add`.

GPG signing is broken (nix-gpg removed). Always run jj with:

```bash
jj --config 'signing.behavior="drop"' <command>
```

Standard workflow:

```bash
jj --config 'signing.behavior="drop"' log -r @   # check current revision
jj --config 'signing.behavior="drop"' new -m "..."  # new revision if scope differs
jj --config 'signing.behavior="drop"' describe -m "..."  # update description
```

## Code rules

- No comments in code. If a comment feels necessary, refactor instead.
- English only — no Russian anywhere in source files.
- `kaizen.py` is the only orchestrator; do not add new Python files unless adding a `post_install.py` to a feature.
- Package names must be valid for their manager — verify before adding (e.g., `go-tools` does not exist in Homebrew).
- Prefer adding features over modifying `kaizen.py`.
- Put idempotent OS configuration in a feature's `post_install.py`; keep privileged or security-sensitive changes opt-in.

## Adding a feature

1. Create `features/<name>/packages.toml` with OS sections.
2. Optionally add `features/<name>/mise.toml` for runtime tools.
3. Enable in `config.example.toml` under `[features]`.
4. For tiling variants: add `features/tiling/variants/<name>/packages.toml` and set `[tiling].variant`.
