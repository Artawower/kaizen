#!/bin/sh
set -eu
unset RIPGREP_CONFIG_PATH
LC_ALL=C
export LC_ALL

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

if [ "${1:-}" = '--help' ]; then
    printf 'Usage: sh discover.sh [REPOSITORY_ROOT [EXISTING_EMPTY_OUTPUT_DIRECTORY]]\n'
    exit 0
fi
[ "$#" -le 2 ] || fail 'Expected at most two arguments; use --help.'
command -v rg >/dev/null 2>&1 || fail 'ripgrep (rg) is required.'

root=${1:-$(jj --config 'signing.behavior="drop"' root)}
root=$(cd "$root" && pwd -P)
[ "$root" != / ] || fail 'The filesystem root cannot be audited with external output.'
if [ "$#" -eq 2 ]; then
    output=$(cd "$2" && pwd -P)
else
    parent=$(cd "${TMPDIR:-/tmp}" && pwd -P)
    case "$parent/" in
        "$root/"*) fail 'The output directory must be outside the audited tree.' ;;
    esac
    output=$(mktemp -d "$parent/kaizen-keybindings.XXXXXX")
fi
case "$output/" in
    "$root/"*) fail 'The output directory must be outside the audited tree.' ;;
esac
[ -z "$(ls -A "$output")" ] || fail 'The output directory must be empty.'
cd "$root"

excluded='.git .jj skills node_modules __pycache__ .cache .pytest_cache .ruff_cache .mypy_cache .venv'
set -- --files --hidden --no-require-git --no-ignore-parent --no-ignore-global --null -g '!.arhive/**'
for directory in $excluded; do
    set -- "$@" -g "!**/$directory/**"
done
if rg "$@" > "$output/.regular.nul"; then
    :
else
    status=$?
    [ "$status" -eq 1 ] || fail "File enumeration failed with exit status $status."
fi

set -- . '(' -path './.arhive'
for directory in $excluded; do
    set -- "$@" -o -name "$directory"
done
set -- "$@" ')' -prune -o -type l -print0
find -P "$@" > "$output/.symlinks.nul" || fail 'Symlink enumeration failed.'

for file in "$output/.regular.nul" "$output/.symlinks.nul"; do
    if rg --null-data --multiline --quiet '[\n\r\t]' "$file"; then
        fail 'Newlines, carriage returns and tabs in filenames are not supported by the line-based inventory.'
    else
        status=$?
        [ "$status" -eq 1 ] || fail "Filename validation failed with exit status $status."
    fi
done
tr '\000' '\n' < "$output/.regular.nul" > "$output/.inventory.lines"
tr '\000' '\n' < "$output/.symlinks.nul" | awk '{sub(/^\.\//, ""); print}' >> "$output/.inventory.lines"
sort -u "$output/.inventory.lines" > "$output/inventory.txt"

pattern='key[_-]?(map|bind|code|board|down|up|press)|bindkey|bindings?|hotkey|shortcut|langmap|langremap|reverse[-_]im|\bkbd\b|\bremap\b|\b(getch|getchar|readchar|read_key)\b|tty\.setraw|\b(nmap|vmap|nnoremap|keymap)[[:space:]]*\(|\balias[[:space:]]+|\b([lr]?(ctrl|control|alt|super|meta|cmd|command|shift)|mod[1-5])([[:space:]]*\+[[:space:]]*|-[a-zA-Z0-9])'
name_pattern='(^|/)[^/]*(key|bind|shortcut|hotkey)[^/]*(/|$)|(^|/)[^/]*rc(\.tmpl)?$|(^|/)(config|init|aliases)(\.[^/]+)?$'
printf '%s\n' "$pattern" > "$output/search-pattern.txt"
: > "$output/.text-files"
: > "$output/.name-matches"
: > "$output/.content-matches"
: > "$output/matches.txt"
: > "$output/filtered.tsv"
: > "$output/symlinks.txt"

while IFS= read -r path; do
    if [ -L "$path" ]; then
        printf '%s\n' "$path" >> "$output/symlinks.txt"
        printf '%s\tsymlink-not-followed\n' "$path" >> "$output/filtered.tsv"
        continue
    fi
    [ -f "$path" ] || fail "An enumerated file disappeared: $path"
    if [ -s "$path" ]; then
        if grep -Iq -e '' -- "$path"; then
            :
        else
            status=$?
            [ "$status" -eq 1 ] || fail "Text classification failed for $path."
            printf '%s\tbinary\n' "$path" >> "$output/filtered.tsv"
            continue
        fi
    fi
    printf '%s\n' "$path" >> "$output/.text-files"
    if printf '%s\n' "$path" | grep -Eiq -e "$name_pattern"; then
        printf '%s\n' "$path" >> "$output/.name-matches"
    fi
    if rg --color never --no-heading --with-filename --line-number --ignore-case \
        --max-count 8 --max-columns 240 --max-columns-preview \
        -e "$pattern" -- "$path" >> "$output/matches.txt"; then
        printf '%s\n' "$path" >> "$output/.content-matches"
    else
        status=$?
        [ "$status" -eq 1 ] || fail "Binding search failed for $path with exit status $status."
    fi
done < "$output/inventory.txt"

sort -u "$output/.name-matches" "$output/.content-matches" > "$output/candidates.txt"
comm -23 "$output/.text-files" "$output/candidates.txt" > "$output/remainder.txt"
inventory=$(wc -l < "$output/inventory.txt" | tr -d ' ')
candidates=$(wc -l < "$output/candidates.txt" | tr -d ' ')
remainder=$(wc -l < "$output/remainder.txt" | tr -d ' ')
filtered=$(wc -l < "$output/filtered.tsv" | tr -d ' ')
[ "$inventory" -eq "$((candidates + remainder + filtered))" ] || fail 'Inventory partition failed.'

{
    printf 'Root: %s\n' "$root"
    printf 'Inventory: %s\nCandidates: %s\nOther text files: %s\nFiltered files: %s\n' "$inventory" "$candidates" "$remainder" "$filtered"
    printf 'Filesystem symlinks: %s\n' "$(wc -l < "$output/symlinks.txt" | tr -d ' ')"
    printf 'Filename pattern: %s\nContent pattern: %s\n' "$name_pattern" "$pattern"
    printf 'Policy: regular files honor repository ignore files, not parent/global ignores; root .arhive, VCS, skills, dependencies and caches are excluded.\n'
    printf 'Symlinks: structurally enumerated even when ignored; targets are never followed. Resolve ownership and archive/external boundaries before inspecting targets.\n'
    printf 'Scope: lexical leads, not binding or coverage verdicts. Follow loaders; reconcile remainder paths. Matches show at most eight bounded previews per file.\n'
    rg --version
} > "$output/summary.txt"
rm "$output/.regular.nul" "$output/.symlinks.nul" "$output/.inventory.lines" \
    "$output/.text-files" "$output/.name-matches" "$output/.content-matches"
printf 'complete\n' > "$output/READY"
printf '%s\n' "$output"
