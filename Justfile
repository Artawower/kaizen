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

e2e:
    bash tests/e2e/test.sh
