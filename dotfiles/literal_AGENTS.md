# Global agent guidance

Follow the nearest project-specific `AGENTS.md` for repository layout, commands, and coding rules.

## Version control

- Use Jujutsu (`jj`) for all repository version-control work, including instructions written in Git terms in skills, documentation, and tools.
- Translate Git operations to their Jujutsu equivalents. Never invoke `git` directly; `jj git` subcommands are allowed within the requested scope.
- Check `jj root` first. If the repository is not managed by Jujutsu, stop and ask; do not fall back to Git or initialize/migrate the repository without permission.
- Do not push or publish changes without explicit user confirmation.

## External skills are immutable

- Treat externally installed skills as immutable dependencies. Never manually edit, reformat, patch, or add files inside their directories, including scripts, references, and assets.
- Install, restore, and update external skills only from their upstream source through the skill manager or an exact upstream snapshot. Never change a lock-file hash to legitimize a local patch.
- Put runtime compatibility rules in `AGENTS.md` and custom workflows or policies outside external skill directories. If upstream behavior must change, propose an upstream fix or an explicitly managed fork instead of patching the installed copy.
- When a skill says to call a Skill tool and no such tool exists, read the installed skill's `SKILL.md` and follow it. Do not rewrite the external skill to accommodate the runtime.

## Dotfiles

- In chezmoi repositories, resolve deployed files with `chezmoi source-path` instead of assuming the source-tree layout.
