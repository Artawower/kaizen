# DevCache

DevCache is an opt-in rootless Linux cache router. It is deployed as
`~/.config/scripts/devcache`; setup installs an executable copy at
`~/.local/bin/devcache`. It does not require sudo or install system mount units.

## Routing

Current setup uses per-command routing:

- Ordinary commands use the local cache environment.
- `devcache run -- <command>` selects verified external storage or the local
  fallback once, then starts the command with fixed absolute cache paths.
- Running processes are not redirected when storage availability changes.
- External storage is expected to be mounted already; `--auto-mount` enables
  a best-effort UDisks mount attempt.
- There is no background routing or automatic cleanup.

The selected external directory is `Kaizen/DevCache` on a UUID-verified
filesystem. Local caches are under
`${XDG_CACHE_HOME:-~/.cache}/devcache-local`. The compatibility
`devcache` symlink points at that local directory; it is not a live
attach/detach switch. Device loss during a running command can still cause
I/O errors.

## Configuration and commands

Configuration is JSON at
`${XDG_CONFIG_HOME:-~/.config}/devcache/config.json`, with a validated
`config.json.bak` backup. State is under
`${XDG_STATE_HOME:-~/.local/state}/devcache`.

```sh
devcache devices
devcache devices --all --json
devcache setup --local-only --adapters npm,pip,uv --dry-run
devcache setup --local-only --adapters npm,pip,uv --yes
devcache setup --uuid UUID --adapters bun,npm,pnpm,go,uv,mise --dry-run
devcache status
devcache doctor
devcache run -- npm install
devcache env --shell bash
devcache env --shell xonsh
devcache disable
devcache enable
devcache recover-config
devcache recover-setup
devcache gc
devcache gc --yes
devcache uninstall
```

Setup refuses an existing configuration; uninstall before selecting a new
setup. Dry-run does not install files. Exported shell environment is optional
and uses local paths. The generated environment.d file affects newly launched
processes; `devcache run` needs no shell restart.

Adapters are Bun, npm, pnpm, Go, pip, uv, mise, Cargo, and Python bytecode.
Cargo requires both `--adapters cargo,...` and explicit `--cargo-links`:
registry/git caches are backed up and linked locally, not routed externally.
Project build directories are unchanged.

## Cleanup and preservation

`gc` previews local native cache-cleaning commands. Execution requires
`--yes`, an enabled external configuration, verified external storage,
no detected cache operations, and local cache size above the configured
threshold. Bun, Cargo registry, Go module caches, Python bytecode, and project
directories are not generically deleted. `gc --auto` is a no-op.

Disable and uninstall preserve cache data. Modified generated files are left
untouched; uninstall does not automatically delete the executable. Old routing
configurations require explicit migration, not silent reuse.

## Development checks

`bash tests/devcache.sh` exercises the current JSON schema, dry-run, local
setup, per-command environment, lock contention, config recovery, and
preservation on uninstall in a temporary home. Linux CLI dispatch is simulated
on other hosts. Real devices, UDisks, systemd, external mount transitions, and
power-loss recovery are not covered by this suite.
