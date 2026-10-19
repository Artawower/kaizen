---
name: archive
description: Archive a Kaizen feature in .arhive/ while retaining its catalog section.
disable-model-invocation: true
---

# Archive

Archive the feature or experiment named by the user. Ask if its owning feature is ambiguous.

1. Read repository guidance and inspect jj state. Use a focused revision, preserving unrelated work. Locate the named section in `features/*.toml` and read its `platforms` and `distributions`. Category files group independent features; there is no user feature enable list.
2. Find owned dotfiles, the explicit `post_install` hook and assets, startup entries, and references. Optional `dotfiles` metadata lists repository-relative source paths and is a discovery hint, not a complete ownership map. Preserve shared files and externally installed skills. Inspect shared selectors such as skhd `.load` and symlinks. If they select a profile being archived, agree on a replacement before moving files; stop if that choice or ownership is unresolved.
3. Set `archive = true` inside the feature section. Keep that section, package lists, inline `tools`, hook path, and metadata in the catalog, preserving every sibling section. Move owned dotfiles, hooks, and assets into repository-root `.arhive/<name>/`, preserving repository-relative paths. For example, `dotfiles/dot_config/yabai/` becomes `.arhive/yabai/dotfiles/dot_config/yabai/`. Stop on conflicting archive contents rather than overwrite them.
4. Adapt approved references while preserving shared integrations. The archive flag excludes packages, tools, and hooks, not dotfiles; physical source moves stop managing owned configs. Multiple unarchived implementations may coexist. Keep the existing feature format and shared selector; change its selection only with explicit approval. Ask before changing user files outside the repository.
5. Parse changed TOML, check affected templates, and inspect the jj diff. Search active configuration for dangling references, excluding `.arhive/`. Report moved paths, archive status, retained shared integrations, selector decisions, and follow-up. Distinguish repository edits from unchanged live files and services.

Leave live dotfiles, installed packages, running services, and external user data unchanged. Do not run sync/apply, uninstall tools, or add chezmoi target-removal rules. Keep this a file-editing workflow: no new archive scripts, registries, or tests.
