#!/usr/bin/env bash
set -euo pipefail

KAIZEN=/workspace/target/release/kaizen
FIXTURES=/workspace/tests/e2e/fixtures
COMMON=(--features-dir "$FIXTURES/features" --config "$FIXTURES/config.toml")

step() { printf "\n\033[1;36m== %s ==\033[0m\n" "$*"; }
ok() { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }

step "Setup local dotfiles git repo"
cp -r "$FIXTURES/dotfiles" /tmp/kaizen-e2e-dotfiles
cd /tmp/kaizen-e2e-dotfiles
git init -q -b main
git config user.email test@kaizen.local
git config user.name "Test"
git add .
git commit -q -m "init"
cd /workspace
ok "dotfiles repo at /tmp/kaizen-e2e-dotfiles"

step "kaizen plan"
plan_output="$($KAIZEN "${COMMON[@]}" plan)"
grep -q "e2e" <<<"$plan_output"
ok "plan includes e2e feature"

step "kaizen install --dry-run"
install_dry_run_output="$($KAIZEN "${COMMON[@]}" install --dry-run)"
grep -q "cowsay" <<<"$install_dry_run_output"
ok "dry-run lists cowsay"

step "kaizen install (real apt install)"
$KAIZEN "${COMMON[@]}" install
command -v cowsay >/dev/null || test -x /usr/games/cowsay || {
	echo "cowsay not installed"
	exit 1
}
test -f /tmp/kaizen-e2e-post-install-fired
ok "cowsay installed and post_install hook fired"

step "kaizen apply (auto chezmoi init + apply)"
$KAIZEN "${COMMON[@]}" apply
grep -q "e2e=true layout=qwerty feature=true" "$HOME/.kaizen-e2e-marker"
test -f /tmp/kaizen-e2e-post-apply-fired
ok "marker rendered with chezmoidata and post_apply hook fired"

step "kaizen update --dry-run e2e"
update_dry_run_output="$($KAIZEN "${COMMON[@]}" update --dry-run e2e)"
grep -q "cowsay" <<<"$update_dry_run_output"
ok "update dry-run targets named feature"

printf "\n\033[1;32mAll e2e scenarios passed.\033[0m\n"
