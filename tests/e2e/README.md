# Docker E2E tests

Real end-to-end tests on a clean Linux container — no mocks. Verifies kaizen
against actual `apt`, `chezmoi`, `git`.

## Run

```sh
just e2e
# or
bash tests/e2e/test.sh
```

First run: ~3 minutes (image build + cargo build + apt install of `cowsay`).
Subsequent runs: ~30s with Docker layer cache.

## Scenarios

- `kaizen plan` — prints feature plan
- `kaizen install --dry-run` — lists packages without running upt
- `kaizen install` — actually installs `cowsay` via apt; verifies binary on PATH and `post_install` hook fired
- `kaizen apply` — auto `chezmoi init` from local git repo, writes `.chezmoidata.toml`, runs `chezmoi apply`, verifies template rendered with feature flag and `post_apply` hook fired
- `kaizen update --dry-run e2e` — targeted update by feature name

## Why Linux only

macOS containers are not feasible (Apple licensing + kernel constraints).
For Mac verification: GitHub Actions `macos-latest` runner or VirtualBuddy VM.
