default:
    just --choose

run *args:
    cargo run --bin kaizen -- {{args}}

test:
    cargo test --workspace

check:
    cargo clippy --workspace --all-targets -- -D warnings

build:
    cargo build --release

release-macos *args:
    bash scripts/release-macos-local.sh {{args}}

e2e:
    bash tests/e2e/test.sh

# Uninstall Nix from macOS (pass --dry-run to preview)
nix-uninstall *args:
    bash scripts/nix-uninstall-macos.sh {{args}}


kaizen_dir := justfile_directory()

dev-link:
    ln -s "{{kaizen_dir}}" ~/.local/share/chezmoi

# Apply dotfiles source → home, then upgrade all tools and dependencies
deploy:
    kaizen apply
    kaizen update

# Pull mutable deployed dotfile state back into this repo's dotfiles source
capture:
    #!/usr/bin/env bash
    set -euo pipefail
    source_dir="{{kaizen_dir}}/dotfiles"

    readd_if_exists() {
        if [ -e "$1" ]; then
            chezmoi --source "$source_dir" re-add "$1"
        fi
    }

    capture_dir_if_exists() {
        if [ ! -d "$1" ]; then
            return
        fi
        chezmoi --source "$source_dir" re-add "$1"
        while IFS= read -r -d '' path; do
            chezmoi --source "$source_dir" add "$path"
        done < <(chezmoi --source "$source_dir" unmanaged --path-style absolute --nul-path-separator "$1")
    }

    readd_if_exists "$HOME/.config/nix/flake.lock"
    readd_if_exists "$HOME/.config/mise.lock"
    readd_if_exists "$HOME/.config/kaizen/feature-meta.json"
    capture_dir_if_exists "$HOME/.config/kaizen/decisions"
    capture_dir_if_exists "$HOME/.config/kaizen/user-features"
    readd_if_exists "$HOME/.emacs.d/elpaca.lock"

    readd_if_exists "$HOME/.pi/agent/settings.json"
    readd_if_exists "$HOME/.pi/agent/mcp.json"
    capture_dir_if_exists "$HOME/.pi/agent/agents"
    capture_dir_if_exists "$HOME/.pi/agent/prompts"
    capture_dir_if_exists "$HOME/.pi/themes"

    readd_if_exists "$HOME/.agents/skill-lock.json"
    readd_if_exists "$HOME/skills-lock.json"
    capture_dir_if_exists "$HOME/.agents/skills"

