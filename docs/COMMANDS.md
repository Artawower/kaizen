# Kaizen CLI commands

## Packages

- `kaizen install <source>` — add a package source to the user configuration and resolve it.
 - `--dry-run` — show the planned changes without applying them.
 - `--type <git|local|url>` — optionally specify the source type; otherwise infer it.
- `kaizen uninstall <package>` — remove a package declaration and its managed files/dependencies after confirmation.
- `kaizen enable <package>` — set the package declaration's `enabled` flag to `true`.
- `kaizen disable <package>` — set the package declaration's `enabled` flag to `false` without removing it.
- `kaizen list` — list declared packages and their enabled state.
- `kaizen search <query>` — search available packages (optionally filter with `--tag <tag>`).
- `kaizen outdated [--deps]` — show available package and, optionally, system dependency updates.
- `kaizen update [<package>] [--sync]` — update lockfile revisions; optionally sync the result.

`uninstall` removes the declaration; `disable` preserves it but excludes that package from planning and deployment. Disabled packages do not contribute tags, mutex claims, or required system dependencies.

## Presets

- `kaizen preset list` — list configured presets.
- `kaizen preset add <preset>` — add a preset.
- `kaizen preset remove <preset>` — remove a preset.
- `kaizen preset enable <preset>` / `kaizen preset disable <preset>` — toggle a preset without removing it.

## System

- `kaizen sync [--dry-run]` — deterministically plan and apply local configuration; does not resolve new upstream revisions.
- `kaizen clean` — remove Kaizen-managed garbage not referenced by current state.
- `kaizen bootstrap` — check and install prerequisite tools.
