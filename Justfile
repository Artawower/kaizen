default:
    cargo run --bin kaizen -- --help

run *args:
    cargo run --bin kaizen -- {{args}}

test:
    cargo test --workspace

check:
    cargo clippy --workspace --all-targets -- -D warnings

build:
    cargo build --release
