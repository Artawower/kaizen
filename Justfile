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
