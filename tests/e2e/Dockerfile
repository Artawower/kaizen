FROM rust:1.85-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates sudo

RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin

RUN cargo install --locked --root /usr/local upt

RUN useradd -m -s /bin/bash kaizen \
    && echo 'kaizen ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/kaizen \
    && chown -R kaizen:kaizen /usr/local/cargo

WORKDIR /workspace
RUN chown kaizen:kaizen /workspace
COPY --chown=kaizen:kaizen . .
USER kaizen

RUN cargo build --release --bin kaizen

ENTRYPOINT ["bash", "/workspace/tests/e2e/run.sh"]
