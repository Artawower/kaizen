---
name: unarchive
description: Restore a Kaizen feature from .arhive/ and clear its catalog archive flag.
disable-model-invocation: true
---

# Unarchive

Restore the feature or experiment named by the user. Ask if the target is missing or ambiguous.

1. Read repository guidance and inspect jj state. Use a focused revision, preserving unrelated work. Locate `.arhive/<name>/` and the retained named section in `features/*.toml`. Inspect relevant jj history when adapting old integrations.
2. Determine original paths from the preserved repository-relative tree. Read current configs, the section's packages and inline tools, its explicit hook path, and OS constraints. Adapt older archive layouts to the current catalog rather than reintroducing per-feature manifests. Optional `dotfiles` metadata is a discovery hint, not a complete ownership map. Multiple implementations may coexist; restoring one does not select a running WM or disable another. Ask before changing user files outside the repository.
3. Move archived files back to their original paths. Compare existing destinations and ask before replacing differing content; stop until conflicts are resolved explicitly. Keep shared selectors such as skhd `.load` or symlinks on their current profile unless switching was requested. Merge only required entries into shared files, preserving unrelated changes and externally installed skills. Adapt obsolete integrations rather than restoring whole old shared configs.
4. Reconnect required references. After restoring all required files, remove `archive = true` from the feature section, preserving sibling sections; omission means active, so do not add `archive = false`. Preserve package lists, inline tools, hook paths, OS constraints, VCS backend, and shortcut semantics. There is no user feature flag to enable.
5. Parse changed TOML, check affected templates, and inspect the jj diff. Confirm references point to existing files. Remove only empty archive directories; retain anything not restored and leave the feature archived when required files are missing. Report paths, adaptations, conflicts, the unchanged or explicitly selected profile, and follow-up. Distinguish repository edits from unchanged live files and services.

Leave live dotfiles, installed packages, running services, and external user data unchanged. Do not run sync/apply, install tools, or add chezmoi target-removal rules. Keep this a file-editing workflow: no new archive scripts, registries, or tests.
