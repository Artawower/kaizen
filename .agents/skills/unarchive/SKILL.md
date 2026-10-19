---
name: unarchive
description: Restore a Kaizen feature or experiment from .arhive/ and reconnect its repository dependencies and integrations.
disable-model-invocation: true
---

# Unarchive

Restore the application, feature, variant, or experiment named by the user. Ask if the target is missing or ambiguous.

1. Read repository guidance and inspect jj state. Use a focused revision, preserving unrelated work. Locate the snapshot under repository-root `.arhive/<name>/` and inspect its files and the relevant jj history.
2. Determine original paths from the preserved repository-relative tree. Read current configs, dependency manifests, hooks, and selectors before restoring. An optional `dotfiles` list is a hint, not a complete ownership map. If another implementation is selected, ask whether to replace it unless the user already requested that switch. Ask before modifying a user config outside the repository.
3. Move archived files back to their original paths. If a destination already exists, compare it and ask before replacing differing content. Merge only the required entries into shared files, preserving unrelated changes and externally installed skills. Adapt obsolete paths or integrations to the current repository rather than restoring whole old shared configs.
4. Restore the target's dependencies and required references, selectors, defaults, and ignore rules. Uncomment only entries belonging to this experiment, retaining shared dependencies and avoiding duplicates. Set `archive = false` only where the existing consumer supports it. Do not invent a feature-format migration or silently change the intended VCS backend or shortcut semantics.
5. Parse changed TOML, check relevant templates, and inspect the jj diff. Confirm restored dependencies and selectors reference existing files. Remove only empty archive directories; retain anything not restored. Report restored paths, adaptations, conflicts, and any required user-config changes.

Leave live dotfiles, installed packages, running services, and external user data unchanged. Do not run sync/apply, install tools, or add chezmoi target-removal rules. Keep this a file-editing workflow: no new archive scripts, registries, feature formats, or tests.
