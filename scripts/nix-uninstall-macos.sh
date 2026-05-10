#!/usr/bin/env bash
# Uninstall Nix from macOS.
#
# Covers both official Nix installer and nix-darwin / Determinate Systems
# setups. Backs up every modified file. Requires explicit typed confirmation.
#
# Usage:
#   just nix-uninstall [--dry-run]
#   bash scripts/nix-uninstall-macos.sh [--dry-run]
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

YEL='\033[0;33m'; GRN='\033[0;32m'; DIM='\033[2m'; RST='\033[0m'

info()   { printf "  ${DIM}→${RST}  %s\n" "$*"; }
ok()     { printf "  ${GRN}✓${RST}  %s\n" "$*"; }
warn()   { printf "  ${YEL}⚠${RST}  %s\n" "$*"; }
header() { printf "\n${DIM}── %s ────────────────────────────────────────${RST}\n" "$*"; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf "  ${DIM}[dry]${RST} %s\n" "$*"
  else
    "$@"
  fi
}

ts() { date +%Y%m%d%H%M%S; }

backup() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local bak="$f.bak-nix-uninstall-$(ts)"
  run sudo cp "$f" "$bak"
  if [[ "$DRY_RUN" == "0" ]]; then ok "backed up → $bak"; fi
}

# ── Guards ────────────────────────────────────────────────────────────────────

[[ "$(uname -s)" == "Darwin" ]] || { printf "macOS only.\n" >&2; exit 1; }

if ! diskutil info /nix >/dev/null 2>&1 && [[ ! -d /nix ]]; then
  warn "/nix not found — Nix may already be removed."
  exit 0
fi

# ── Confirmation ──────────────────────────────────────────────────────────────

printf "\nThis script will remove Nix from macOS:\n"
printf "  • stop and delete Nix launch daemons\n"
printf "  • remove nixbld users/group (_nixbld1…N and nixbld1…N)\n"
printf "  • clean Nix shell blocks from /etc/zshrc /etc/bashrc /etc/bash.bashrc\n"
printf "  • clean /etc/fstab and /etc/synthetic.conf\n"
printf "  • delete /etc/nix and ~/.nix-* profile files\n"
printf "  • delete the Nix Store APFS volume (/nix)\n"
printf "\nAll modified files are backed up first.\n"

if [[ "$DRY_RUN" == "1" ]]; then
  printf "\n${YEL}DRY-RUN — no changes will be made.${RST}\n\n"
else
  printf "\n"
  read -r -p "Type DELETE NIX to continue: " confirm
  [[ "$confirm" == "DELETE NIX" ]] || { printf "Aborted.\n"; exit 1; }
  printf "\n"
  # Keep sudo alive for the duration of the script
  sudo -v
  while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done &
  trap 'kill %1 2>/dev/null || true' EXIT
fi

# ── 1) Launch daemons ─────────────────────────────────────────────────────────

header "1) Launch daemons"

DAEMONS=(
  # Official Nix installer + nix-darwin
  org.nixos.nix-daemon
  org.nixos.darwin-store
  org.nixos.activate-system
  # Determinate Systems
  systems.determinate.nix-installer.nix-hook
  systems.determinate.nix-store
  systems.determinate.nixd
)

for label in "${DAEMONS[@]}"; do
  plist="/Library/LaunchDaemons/$label.plist"
  if [[ -f "$plist" ]]; then
    info "unloading $label"
    run sudo launchctl unload "$plist" 2>/dev/null || true
    run sudo rm -f "$plist"
    if [[ "$DRY_RUN" == "0" ]]; then ok "removed $plist"; fi
  fi
done

# ── 2) Shell init hooks ───────────────────────────────────────────────────────

header "2) Shell init hooks"

clean_shell_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  local changed=0

  # Pattern A: official Nix installer block  # Nix … # End Nix
  if grep -q "# End Nix" "$f" 2>/dev/null; then
    backup "$f"
    if [[ "$DRY_RUN" == "1" ]]; then
      info "[dry] remove '# Nix … # End Nix' block from $f"
    else
      sudo perl -0pi -e \
        's/\n?# Nix\nif \[ -e '"'"'\/nix[^'"'"']*nix-daemon\.sh'"'"' \]; then\n[^\n]*\nfi\n# End Nix\n?/\n/g' \
        "$f"
      ok "removed Nix block from $f"
      changed=1
    fi
  fi

  # Pattern B: nix-darwin __NIX_DARWIN_SET_ENVIRONMENT_DONE block
  if grep -q "__NIX_DARWIN_SET_ENVIRONMENT_DONE" "$f" 2>/dev/null; then
    if [[ "$changed" == "0" ]]; then backup "$f"; fi
    if [[ "$DRY_RUN" == "1" ]]; then
      info "[dry] remove nix-darwin env block from $f"
    else
      sudo perl -0pi -e \
        's/\n?if \[ -z "\$__NIX_DARWIN_SET_ENVIRONMENT_DONE" \]; then\n[^\n]*\nfi\n?/\n/g' \
        "$f"
      ok "removed nix-darwin block from $f"
    fi
  fi
}

for f in /etc/zshrc /etc/bashrc /etc/bash.bashrc; do
  clean_shell_file "$f"
done

# ── 3) nixbld users and group ─────────────────────────────────────────────────

header "3) nixbld users and group"

# Determinate uses _nixbldN (underscore), official uses nixbldN — handle both
while IFS= read -r u; do
  [[ -z "$u" ]] && continue
  info "deleting user $u"
  run sudo dscl . -delete "/Users/$u" 2>/dev/null || true
done < <(dscl . -list /Users 2>/dev/null | grep -E '^_?nixbld' || true)

for group in nixbld _nixbld; do
  if dscl . -read "/Groups/$group" >/dev/null 2>&1; then
    info "deleting group $group"
    run sudo dscl . -delete "/Groups/$group" 2>/dev/null || true
    if [[ "$DRY_RUN" == "0" ]]; then ok "removed group $group"; fi
  fi
done

# ── 4) /etc/fstab ────────────────────────────────────────────────────────────

header "4) /etc/fstab"

if [[ -f /etc/fstab ]] && grep -iE '/nix|Nix.Store' /etc/fstab >/dev/null 2>&1; then
  backup /etc/fstab
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry] remove /nix and Nix Store entries from /etc/fstab"
  else
    tmp="$(mktemp)"
    awk '!($2=="/nix") && !/Nix\\040Store/ && !/Nix[[:space:]]Store/' \
      /etc/fstab > "$tmp"
    sudo cp "$tmp" /etc/fstab
    rm -f "$tmp"
    ok "cleaned /etc/fstab"
  fi
else
  info "no Nix entries in /etc/fstab"
fi

# ── 5) /etc/synthetic.conf ────────────────────────────────────────────────────

header "5) /etc/synthetic.conf"

if [[ -f /etc/synthetic.conf ]] && grep -qE '^nix([[:space:]]|$)' /etc/synthetic.conf; then
  backup /etc/synthetic.conf
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry] remove 'nix' line from /etc/synthetic.conf"
  else
    tmp="$(mktemp)"
    grep -vE '^nix([[:space:]]|$)' /etc/synthetic.conf > "$tmp" || true
    if [[ -s "$tmp" ]]; then
      sudo cp "$tmp" /etc/synthetic.conf
    else
      sudo rm -f /etc/synthetic.conf
    fi
    rm -f "$tmp"
    ok "cleaned /etc/synthetic.conf"
  fi
else
  info "no 'nix' line in /etc/synthetic.conf"
fi

# ── 6) Config and profile files ───────────────────────────────────────────────

header "6) Config and profile files"

for p in /etc/nix /var/root/.nix-profile /var/root/.nix-defexpr /var/root/.nix-channels; do
  [[ -e "$p" ]] && run sudo rm -rf "$p" && info "removed $p"
done

for p in "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels" \
         "$HOME/.cache/nix" "$HOME/.config/nix"; do
  [[ -e "$p" ]] && run rm -rf "$p" && info "removed $p"
done

# ── 7) Nix Store APFS volume ──────────────────────────────────────────────────

header "7) Nix Store APFS volume"

if diskutil info /nix >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry] diskutil apfs deleteVolume /nix"
  else
    info "deleting APFS volume /nix …"
    if ! sudo diskutil apfs deleteVolume /nix; then
      warn "deleteVolume /nix failed — volume may be locked by kernel."
      warn "Reboot, then run:"
      warn "  sudo diskutil apfs deleteVolume /nix"
      vols="$(diskutil list 2>/dev/null | grep 'Nix Store' || true)"
      [[ -n "$vols" ]] && { warn "or use the disk identifier:"; printf "%s\n" "$vols"; }
      exit 1
    fi
    ok "Nix Store volume deleted"
  fi
elif [[ -d /nix ]]; then
  warn "/nix is a plain directory — removing"
  run sudo rm -rf /nix
else
  info "no /nix volume or directory"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

printf "\n${GRN}Done.${RST}\n"

if [[ "$DRY_RUN" == "0" ]]; then
  printf "\nVerification commands:\n"
  printf "  command -v nix\n"
  printf "  diskutil list | grep -i 'Nix Store'\n"
  printf "  dscl . -list /Users | grep -E '^_?nixbld'\n"
  printf "\nOpen a new terminal for shell changes to take effect.\n"
  printf "A stale empty /nix directory may remain until reboot — that is normal.\n"
fi
