#!/bin/sh
set -eu

script=$(cd "$(dirname "$0")" && pwd -P)/discover.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/kaizen-discovery-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
root=$work/source
first=$work/first
second=$work/second
mkdir -p "$root/app" "$root/.arhive/old" "$root/.jj" "$root/.git" \
    "$root/external/skills/demo" "$root/node_modules/pkg" "$root/__pycache__" \
    "$root/ignored" "$root/docs" "$root/tests" "$root/nested" "$first" "$second"
printf 'app/\n' > "$work/.ignore"
printf 'ignored/\n' > "$root/.gitignore"
printf 'hidden.conf\n' > "$root/nested/.ignore"
printf '[keys]\nfocus_down = "alt+j"\n' > "$root/app/config with spaces.toml"
printf '(global-set-key (kbd "C-j") '\''next-line)\n' > "$root/app/README.org"
printf '(global-set-key (kbd "C-k") '\''previous-line)\n' > "$root/docs/runtime.org"
printf 'read_key()\n' > "$root/tests/interactive.sh"
printf 'alias п = gitu\n' > "$root/app/aliases.nu"
printf 'source commands.conf\n' > "$root/app/config.nu"
printf 'langmap=тk\n' > "$root/app/commands.conf"
printf 'cursor { size 24; }\n' > "$root/app/cursor.kdl"
printf 'keymap\000binary\n' > "$root/app/binary-keymap.otf"
printf 'A shortcut example in passive documentation.\n' > "$root/notes.md"
printf 'keybinding = Ctrl+j\n' > "$root/nested/hidden.conf"
printf 'hotkey = Ctrl+j\n' > "$root/-key.conf"
awk 'BEGIN {for (i=0; i<20; i++) {printf "keybinding = "; for (j=0; j<500; j++) printf "x"; printf "\n"}}' > "$root/app/long.conf"
: > "$root/app/empty_binds.kdl"
: > "$root/.inputrc"
for path in .arhive/old .jj .git external/skills/demo node_modules/pkg __pycache__ ignored; do
    printf 'bind = Ctrl+j\n' > "$root/$path/keys.txt"
done
ln -s "$root/.arhive/old" "$root/app/archive-link"
ln -s "$root/.arhive/old/keys.txt" "$root/app/key-link"
ln -s "$root/app/missing.conf" "$root/app/broken-link"
ln -s "$root/app" "$root/app/loop-link"
ln -s "$work" "$root/ignored/external-link"
printf '%s\n' '--invalid-config-for-discovery-test' > "$work/ripgrep.conf"
RIPGREP_CONFIG_PATH="$work/ripgrep.conf" sh "$script" "$root" "$first" > "$work/first-path"
RIPGREP_CONFIG_PATH="$work/ripgrep.conf" sh "$script" "$root" "$second" > "$work/second-path"
for path in 'app/config with spaces.toml' app/README.org app/commands.conf app/empty_binds.kdl .inputrc notes.md docs/runtime.org tests/interactive.sh app/aliases.nu app/config.nu -key.conf; do
    grep -Fxq -- "$path" "$first/candidates.txt"
done
grep -Fxq 'app/cursor.kdl' "$first/remainder.txt"
grep -Fq 'app/config with spaces.toml:2:' "$first/matches.txt"
[ "$(grep -c '^app/long.conf:' "$first/matches.txt")" -eq 8 ]
awk 'length($0) > 400 {exit 1}' "$first/matches.txt"
grep -Fq "$(printf 'app/binary-keymap.otf\tbinary')" "$first/filtered.tsv"
for path in app/archive-link app/key-link app/broken-link app/loop-link ignored/external-link; do
    grep -Fxq "$path" "$first/inventory.txt"
    grep -Fxq "$path" "$first/symlinks.txt"
    grep -Fq "$(printf '%s\tsymlink-not-followed' "$path")" "$first/filtered.tsv"
done
if grep -Eq 'binary-keymap|archive-link|key-link|loop-link|broken-link|(^|/)(\.arhive|\.git|\.jj|skills|node_modules|__pycache__|ignored)/|nested/hidden.conf' "$first/candidates.txt"; then
    printf 'Excluded data leaked into candidates.\n' >&2
    exit 1
fi
if grep -Eq '(^|/)(\.arhive|\.git|\.jj|skills|node_modules|__pycache__)/|ignored/keys.txt|nested/hidden.conf|loop-link/' "$first/inventory.txt"; then
    printf 'Excluded data leaked into the inventory.\n' >&2
    exit 1
fi
for file in inventory.txt candidates.txt remainder.txt matches.txt filtered.tsv symlinks.txt search-pattern.txt summary.txt READY; do
    cmp "$first/$file" "$second/$file"
done
[ "$(wc -l < "$first/inventory.txt")" -eq "$(($(wc -l < "$first/candidates.txt") + $(wc -l < "$first/remainder.txt") + $(wc -l < "$first/filtered.tsv")))" ]
mkdir "$root/inside-output"
if sh "$script" "$root" "$root/inside-output" > "$work/inside.log" 2>&1; then
    printf 'An in-tree output directory was accepted.\n' >&2
    exit 1
fi
[ -z "$(ls -A "$root/inside-output")" ]
if sh "$script" "$root" "$first" > "$work/overwrite.log" 2>&1; then
    printf 'A nonempty output directory was accepted.\n' >&2
    exit 1
fi
for file in inventory.txt candidates.txt remainder.txt matches.txt filtered.tsv symlinks.txt search-pattern.txt summary.txt READY; do
    cmp "$first/$file" "$second/$file"
done
mkdir "$root/temporary-output"
if TMPDIR="$root/temporary-output" sh "$script" "$root" > "$work/temporary-output.log" 2>&1; then
    printf 'An in-tree temporary directory was accepted.\n' >&2
    exit 1
fi
[ -z "$(ls -A "$root/temporary-output")" ]
mkdir "$work/relative-output"
(cd "$work" && sh "$script" "$root" relative-output > relative-path)
[ "$(wc -l < "$work/relative-output/candidates.txt")" -eq "$(wc -l < "$first/candidates.txt")" ]
mkdir "$work/bin" "$work/search-error-output" "$work/enumeration-error-output" "$work/link-error-output"
real_rg=$(command -v rg)
printf '#!/bin/sh\ncase "$1" in --color) exit 2 ;; esac\nexec "$REAL_RG" "$@"\n' > "$work/bin/rg"
chmod +x "$work/bin/rg"
if PATH="$work/bin:$PATH" REAL_RG="$real_rg" sh "$script" "$root" "$work/search-error-output" > "$work/search-error.log" 2>&1; then
    printf 'A search failure was silently accepted.\n' >&2
    exit 1
fi
grep -Fq 'Binding search failed for' "$work/search-error.log"
[ ! -e "$work/search-error-output/READY" ]
printf '#!/bin/sh\ncase "$1" in --files) exit 2 ;; esac\nexec "$REAL_RG" "$@"\n' > "$work/bin/rg"
if PATH="$work/bin:$PATH" REAL_RG="$real_rg" sh "$script" "$root" "$work/enumeration-error-output" > "$work/enumeration-error.log" 2>&1; then
    printf 'An enumeration failure was silently accepted.\n' >&2
    exit 1
fi
grep -Fq 'File enumeration failed' "$work/enumeration-error.log"
[ ! -e "$work/enumeration-error-output/READY" ]
rm "$work/bin/rg"
printf '#!/bin/sh\nexit 2\n' > "$work/bin/find"
chmod +x "$work/bin/find"
if PATH="$work/bin:$PATH" sh "$script" "$root" "$work/link-error-output" > "$work/link-error.log" 2>&1; then
    printf 'A symlink enumeration failure was silently accepted.\n' >&2
    exit 1
fi
grep -Fq 'Symlink enumeration failed' "$work/link-error.log"
[ ! -e "$work/link-error-output/READY" ]
for character in "$(printf '\nX')" "$(printf '\t')" "$(printf '\r')"; do
    character=${character%X}
    invalid="bad${character}name"
    : > "$root/$invalid"
    output=$(mktemp -d "$work/invalid.XXXXXX")
    if sh "$script" "$root" "$output" > "$work/invalid.log" 2>&1; then
        printf 'An unsupported filename was silently accepted.\n' >&2
        exit 1
    fi
    grep -Fq 'filenames are not supported' "$work/invalid.log"
    [ ! -e "$output/READY" ]
    rm "$root/$invalid"
done
mkdir "$work/empty" "$work/empty-output"
sh "$script" "$work/empty" "$work/empty-output" > "$work/empty-path"
[ ! -s "$work/empty-output/inventory.txt" ]
[ -f "$work/empty-output/READY" ]
printf 'Discovery fixture checks passed.\n'
