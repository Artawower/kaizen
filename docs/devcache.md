# DevCache

DevCache is an opt-in Linux CLI for routing selected per-user developer caches to a stable location, optionally bind-mounted from a USB SSD. The CLI is installed as `~/.config/scripts/devcache`. It does not change system configuration until external-storage setup is explicitly confirmed.

## Storage and transition model

- Stable path: `${XDG_CACHE_HOME:-~/.cache}/devcache`
- Local fallback: `${XDG_CACHE_HOME:-~/.cache}/devcache-local`
- A root-owned systemd mount unit bind-mounts the local fallback over the stable path. A root-owned helper can instead bind only the selected SSD's `Kaizen/DevCache` subdirectory over that path.
- The SSD must already be mounted by the desktop/file manager. DevCache never mounts or unmounts the partition itself, takes over the whole partition, or formats it. It checks UUID, filesystem type, mount source, and the dedicated subdirectory before switching.
- Local and SSD caches are independent. DevCache does not merge them on attach/detach and does not promise the local cache is a copy of the SSD. New processes use whichever tree is mounted at the stable path; the untouched local tree remains available for offline use.
- Switching is deferred while detected cache users are active. Detection is best-effort, not a kernel-level lock against unrelated processes. Unexpected removal while files are open can still cause I/O errors.

Only writable USB filesystems of Btrfs, ext4, or XFS are eligible. Internal/system devices, read-only devices, unsupported filesystems, and the root/home UUIDs are excluded. Setup displays the UUID, filesystem, and available space for confirmation. If the SSD is not mounted, use `devcache setup --local-only` or mount it in the file manager and retry.

The privileged integration consists of a root-owned helper and UUID config, root-owned systemd/udev/tmpfiles rules, and a user-owned cleanup timer for external configurations. The tmpfiles rule recreates the volatile shared lock with root ownership, the user's primary group, and mode `0660` at boot before the reconciliation service can use it. The root helper validates ownership, modes, config ancestry, device UUID/filesystem, mount source, and the exact `Kaizen/DevCache` subdirectory; it never runs the user-owned Python CLI as root. Generated units are verified before installation. Uninstall removes only unchanged DevCache-owned files and preserves modified or symlinked files.

## Supported adapters

| Adapter | Configuration |
| --- | --- |
| Bun | `bunfig.toml` `install.cache.dir`; global package directory is unchanged |
| npm | `npm_config_cache` |
| pnpm | `pnpm_config_store_dir` |
| Go | `GOCACHE` and `GOMODCACHE` |
| Cargo | `~/.cargo/registry` and `~/.cargo/git` symlink to the stable path; `target/` is unchanged |
| Python bytecode | `PYTHONPYCACHEPREFIX` |
| pip | `PIP_CACHE_DIR` |
| uv | `UV_CACHE_DIR` |
| mise | `MISE_CACHE_DIR` |

DNF5, Flatpak, and Podman are unsupported. They are not considered disposable user caches.

## Commands

```sh
devcache setup --dry-run --local-only
devcache setup                         # interactive storage and adapter selection
devcache setup --device-uuid UUID --caches bun,npm,go --yes
devcache status
devcache status --json
devcache doctor
devcache config                        # print current config
devcache enable
devcache disable
devcache sync --dry-run
devcache sync
devcache gc --dry-run
devcache gc
devcache gc --auto --dry-run
devcache gc --local --dry-run
devcache uninstall --dry-run
devcache uninstall
```

Dry-run commands do not apply their planned changes. `--yes` skips confirmation; it does not imply dry-run. Setup leaves caches in place by default. Optional `--migrate-existing` copies into a new cache destination through a staging directory, preserves the source, and refuses to merge into an existing destination. DevCache does not use network access for migration.

`sync` intentionally does not merge cache trees: manager caches contain indexes, metadata, and links with tool-specific semantics. It is currently a safety-preserving no-op; tools repopulate an independent SSD cache through normal operations. `gc --local` is also intentionally a no-op so offline fallback data is never cleaned.

## Cleanup policy

Only external configurations install the per-user 12-hour cleanup timer. Before cleanup, DevCache verifies that the configured SSD source is still mounted, the stable path is the UUID/filesystem-verified `Kaizen/DevCache` bind mount, and no detected cache operation is active. Cleanup is never directed at the local fallback. If the SSD source is absent or cannot be verified, cleanup does nothing.

Manual `gc` can invoke native cleanup commands for selected adapters: npm (`npm cache clean`), pip (`pip cache purge`), uv (`uv cache clean`), Go build cache (`go clean -cache`), and mise (`mise cache prune --yes`). Automatic cleanup always considers mise pruning and adds supported native cleaners when measured supported-cache size exceeds the configured 10 GiB default. These commands can clear whole manager caches; the byte limit is a trigger, not a guarantee that a particular size will be reclaimed. Inspect the exact planned commands with `gc --dry-run` first.

pnpm, Bun, Cargo, Python bytecode, and Go module caches are excluded from cleanup. Bun's setting changes only its download cache; its global package directory is neither redirected nor cleaned. Cargo project `target/` directories are not moved. Automatic cleanup is native-tool based, not generic age/mtime deletion.

## Data preservation and rollback

Configuration is stored in `~/.config/devcache/config.toml`; state backups are under `~/.local/state/devcache/backups`. Uninstall restores unchanged managed Bun/Cargo settings, removes generated environment/Xonsh files only when they still match their recorded hashes, and preserves user-modified or symlinked files. Cache trees and state backups are retained. If a configuration file was edited after DevCache installed it, uninstall leaves that file in place and reports it.

For a future real-device trial, keep the SSD mounted through the file manager and first run `devcache setup --dry-run --device-uuid UUID --caches ...`. Check `devcache status` and `devcache doctor` before relying on the external cache. To roll back, close builds/package managers, run `devcache disable`, verify status shows the local fallback, then run `devcache uninstall` if removing DevCache entirely. Do not force-unmount the SSD. If `disable` refuses because activity is detected or a managed file was changed, stop and inspect the reported paths/processes rather than deleting files or forcing a transition.

Environment changes affect newly launched processes. Xonsh sources the generated snippet on startup; GUI applications inherited from an already-running compositor may need a logout/login. The DevCache test suite only uses temporary homes and mock filesystems; no real installation, SSD, or user cache is part of validation.

## Development checks

`bash tests/devcache.sh` exercises local-only setup, isolated copy migration, environment/Xonsh loading, lock contention, status/doctor, GC planning and fallback protection, modified-config preservation, and generated unit validation. `bash tests/devcache-mount.sh` exercises attach/detach, repeated activation, active-operation refusal, local fallback, and UUID mismatch in a private mount namespace with temporary filesystems. Both are development tests only; they do not validate real-device UDisks behavior, power-loss recovery, SELinux enforcement, or system-wide installation/rollback.
