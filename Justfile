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
