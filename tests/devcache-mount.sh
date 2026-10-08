#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/dotfiles/dot_config/scripts/executable_devcache-mount-helper"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! unshare --user --map-root-user --mount true >/dev/null 2>&1; then
    printf 'DevCache mount integration tests skipped: unprivileged mount namespaces are unavailable.\n'
    exit 0
fi

ssd="$tmp/ssd device"
test_home="$tmp/home"
cache_root="$test_home/.cache/devcache"
local_root="$test_home/.cache/devcache-local"
mkdir -p "$tmp/config" "$cache_root" "$local_root" "$ssd"
chmod 700 "$tmp/config" "$test_home" "$test_home/.cache" "$cache_root" "$local_root"
printf 'local cache\n' >"$local_root/marker"
printf 'local cache\n' >"$cache_root/marker"

DEVCACHE_TEST_ROOT="$tmp" DEVCACHE_TEST_HELPER="$helper" unshare --user --map-root-user --mount bash -s -- "$tmp" "$helper" "$ssd" <<'NS'
set -euo pipefail
root=$1
helper=$2
ssd=$3
test_home="$root/home"
cache_root="$test_home/.cache/devcache"
local_root="$test_home/.cache/devcache-local"
uuid=12345678-1234-1234-1234-123456789abc
mount -t tmpfs tmpfs "$ssd"
mkdir -p "$ssd/Kaizen/DevCache"
chmod 700 "$ssd/Kaizen/DevCache"
printf 'ssd cache\n' >"$ssd/Kaizen/DevCache/marker"
mount --bind "$local_root" "$cache_root"
printf 'CACHE_UID=0\nCACHE_GID=0\nDEVICE_UUID=%s\nDEVICE_FS=btrfs\nCACHE_ROOT=%s\nLOCAL_ROOT=%s\nSSD_SUBDIR=Kaizen/DevCache\n' "$uuid" "$cache_root" "$local_root" >"$root/config/0.conf"
chmod 600 "$root/config/0.conf"
export DEVCACHE_TEST_MODE=1 DEVCACHE_TEST_CONFIG_DIR="$root/config" DEVCACHE_TEST_HOME_ROOT="$test_home" DEVCACHE_TEST_SOURCE_ROOT="$ssd" DEVCACHE_TEST_UUID_OVERRIDE="$uuid" DEVCACHE_TEST_FS_OVERRIDE=btrfs
assert_local() {
    [[ $(findmnt -n -o FSROOT --target "$cache_root" | tail -n 1) != "/Kaizen/DevCache" ]]
}
trap 'umount "$cache_root" 2>/dev/null || true; umount "$ssd" 2>/dev/null || true' EXIT

mkdir -p "$root/proc-cargo" "$root/proc-bun"
printf 'cargo\n' >"$root/proc-cargo/comm"
printf 'cargo\0build\0--release\0' >"$root/proc-cargo/cmdline"
printf 'bun\n' >"$root/proc-bun/comm"
printf 'bun\0install\0' >"$root/proc-bun/cmdline"
bash "$helper" is-cache-operation 0 "$root/proc-cargo"
bash "$helper" is-cache-operation 0 "$root/proc-bun"
chmod 644 "$root/config/0.conf"
if bash "$helper" activate 0 >/dev/null 2>&1; then
    printf 'DevCache sourced a group/world-readable root config.\n' >&2
    exit 1
fi
chmod 600 "$root/config/0.conf"
ln "$root/config/0.conf" "$root/config/linked.conf"
if bash "$helper" activate 0 >/dev/null 2>&1; then
    printf 'DevCache sourced a hard-linked root config.\n' >&2
    exit 1
fi
rm "$root/config/linked.conf"
ln -s "$root/config" "$root/config-link"
if DEVCACHE_TEST_CONFIG_DIR="$root/config-link" bash "$helper" activate 0 >/dev/null 2>&1; then
    printf 'DevCache followed a symlinked privileged config directory.\n' >&2
    exit 1
fi
chmod 755 "$ssd/Kaizen/DevCache"
bash "$helper" activate 0 >/dev/null 2>&1
assert_local
chmod 700 "$ssd/Kaizen/DevCache"
DEVCACHE_TEST_SELINUX_ENFORCING=1 DEVCACHE_TEST_SELINUX_CONTEXT='system_u:object_r:user_tmp_t:s0' bash "$helper" activate 0 >/dev/null 2>&1
assert_local
DEVCACHE_TEST_FS_OVERRIDE=ext4 bash "$helper" activate 0 >/dev/null 2>&1
assert_local
bash "$helper" activate 0
[[ $(cat "$cache_root/marker") == "ssd cache" ]]
mountpoint -q "$ssd"
bash "$helper" activate 0
[[ $(findmnt -n -o FSROOT --target "$cache_root" | tail -n 1) == "/Kaizen/DevCache" ]]

bash -c 'cd "$1" && exec sleep 30' devcache-active-build "$cache_root" &
active_pid=$!
sleep 0.2
if bash "$helper" deactivate 0 >/dev/null 2>&1; then
    printf 'DevCache unmounted while a process was using the cache.\n' >&2
    kill "$active_pid" 2>/dev/null || true
    exit 1
fi
if ! umount "$ssd"; then
    printf 'The isolated SSD filesystem could not be detached for the disconnect test.\n' >&2
    kill "$active_pid" 2>/dev/null || true
    exit 1
fi
if bash "$helper" reconcile 0 >/dev/null 2>&1; then
    printf 'DevCache switched storage while a process was using the cache.\n' >&2
    kill "$active_pid" 2>/dev/null || true
    exit 1
fi
[[ $(findmnt -n -o FSROOT --target "$cache_root" | tail -n 1) == "/Kaizen/DevCache" ]]
kill "$active_pid" 2>/dev/null || true
wait "$active_pid" 2>/dev/null || true
bash "$helper" reconcile 0
[[ $(cat "$cache_root/marker") == "local cache" ]]

mount -t tmpfs tmpfs "$ssd"
mkdir -p "$ssd/Kaizen/DevCache"
DEVCACHE_TEST_UUID_OVERRIDE=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa bash "$helper" activate 0
[[ $(cat "$cache_root/marker") == "local cache" ]]
[[ $(findmnt -n -o FSROOT --target "$cache_root" | tail -n 1) != "/Kaizen/DevCache" ]]
printf 'DevCache temporary-filesystem mount lifecycle tests passed.\n'
NS
