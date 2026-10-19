---
name: archive
description: Move a Kaizen feature or experiment into .arhive/ and disable its repository dependencies and integrations.
disable-model-invocation: true
---

# Archive

Archive the application, feature, variant, or experiment named by the user. Ask if the target is missing or ambiguous.

1. Read repository guidance and inspect jj state. Use a focused revision, preserving unrelated work. Inspect committed defaults and the effective user selection before moving an active feature; ask which replacement or disabled state is wanted if the request does not say.
2. Find owned dotfiles, dependency manifests, hooks, startup entries, and references. An optional `dotfiles` list is a hint: resolve its path convention and search for additional integrations. Preserve shared files and packages needed by other features; ask about uncertain ownership. Externally installed skills remain untouched.
3. Move owned files into repository-root `.arhive/<name>/`, preserving their repository-relative paths. For example, `dotfiles/dot_config/yabai/` becomes `.arhive/yabai/dotfiles/dot_config/yabai/`. Keep the archive outside the chezmoi source. Stop on conflicting archive contents rather than overwrite them.
4. Disable remaining active dependencies and references. Use an existing `archive = true` field only if its consumer actually supports it; otherwise comment out the target's TOML entries or move its dedicated manifests with the files. Preserve enough context to reverse the change and keep TOML valid. Update repository defaults, examples, selectors, and ignore rules only where needed. Current Kaizen rejects missing feature names even when set to `false`, so comment out or remove such entries when moving their feature directory. Ask before modifying a user config outside the repository.
5. Parse changed TOML, check relevant remaining templates, and inspect the jj diff. Search active configuration for dangling references, excluding `.arhive/`. Report moved paths, dependency changes, retained shared integrations, and any required user-config changes.

Leave live dotfiles, installed packages, running services, and external user data unchanged. Do not run sync/apply, uninstall tools, or add chezmoi target-removal rules. Keep this a file-editing workflow: no new archive scripts, registries, feature formats, or tests.
