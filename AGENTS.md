# Kaizen — Agent Reference

Kaizen is a dotfiles and developer environment manager. No Nix, no Rust.
Stack: **Python 3.11+**, **chezmoi** (dotfiles), **mise** (runtimes), **brew/dnf/apt** (packages).

The installer reuses Python 3.11+ or bootstraps an isolated Python through uv.
Native package managers are runtime dependencies of `sync`/`update`, not installer
prerequisites. Missing Homebrew is offered interactively through its official installer.

## Repository layout

```
features/*.toml     # category catalogs, one named section per feature
features/hooks/     # only executable hooks and their assets

dotfiles/           # chezmoi source tree (dot_config/ → ~/.config/, etc.)
kaizen.py           # orchestrator — the only Python source file
config.example.toml # authoritative user intent, preferences, and requirements
Justfile            # thin wrappers: sync, update, bump, capture, status, install
```

## Feature anatomy

Add a named section to a category file such as `features/editor.toml`:

```toml
[example]
description = "Example CLI tools"
packages = ["jq"]
tools = { go = "latest" }
```

Use `packages` for shared native dependencies, flat manager keys for additions, and inline `package_names` for naming exceptions. Kaizen resolves known aliases and deduplicates active declarations before installation. Use an inline `tools` table for mise versions. Optional `brew_args` is a native-package-to-flags table. A `post_install` path is repository-relative, such as `features/hooks/emacs/post_install.py`; colocate its assets with the script. There are no per-feature package or mise files. See `docs/feature-format.org` when changing the schema.

Omitted `platforms` means macOS and Linux; restrict a whole recipe with `platforms = ["macos"]` or `["linux"]`. Optional `distributions` restricts Linux distro IDs. The same filter applies to native packages, mise, and hooks. `kaizen sync` generates `~/.config/mise.toml` from applicable `tools` entries. Feature names are unique across category files; there is no inheritance or variant selection. Dotfiles are independent: chezmoi applies source files with general platform exclusions; archive owned files physically to stop managing them.

## Configuration authority

Before changing application configuration, read `config.example.toml` in full
and preserve its existing requirements.

Treat `config.example.toml` as read-only unless the user explicitly asks to
edit it or record a requirement there. Requests to fix bugs, change application
behavior, add shortcuts, or install software do not grant this permission.

When editing is authorized, change only the requested entries. Add explanatory
comments, descriptive keys, or implementation notes only when explicitly requested.

Application-specific changes belong in native configs. Software, versions,
platforms, and installation hooks belong in `features/*.toml`.

If a request conflicts with an existing requirement, report the conflict and
ask which should take precedence.

Before finishing, verify that `config.example.toml` is unchanged unless its
modification was explicitly authorized.

For keybinding additions, changes, or restored configs, agents MUST follow `[keyboard]` and `[keyboard.aliases.ru]` in `config.example.toml`. Determine whether the application consumes characters or physical key codes; compensate physical inputs and outputs for `layout`. Use native language-mapping facilities or explicit command aliases, preserving sequences, modifiers, and Shift without altering text insertion. Verify Latin/Russian command equivalence and report unsupported mappings or collisions instead of silently skipping them.

`[terminal].shell` selects the preferred interactive shell. Apply the required completion provider in `[terminal].completion` to every managed interactive shell, including newly added or restored shells. Its `source` URL is upstream reference material for adaptation, not an installation recipe. Noninteractive command interpreters are unaffected.

## User config

`~/.config/kaizen/config.toml` (user edits this, not committed):

```toml
layout = "colemak"

[ui]
font_size = 14
```

`dotfiles/.chezmoidata.toml` contains committed defaults. Chezmoi merges user settings over those defaults. Kaizen writes an ignored `dotfiles/.chezmoidata/99-user.toml` snapshot before applying chezmoi. User `[features]` tables and old variant selectors are rejected; set `archive = true` in unwanted feature sections instead. Dictionaries merge recursively; lists and scalar values are replaced. Refresh the snapshot with `kaizen sync` after changing user settings.

## Key commands

| Command | Effect |
| --- | --- |
| `kaizen` / `kaizen help` | show commands, documentation URL, and config path |
| `kaizen docs` | show documentation, config, and installed source paths |
| `just sync` | install packages → generate mise.toml → mise install → chezmoi apply |
| `kaizen self-update` | fast-forward a managed installation; unavailable in development mode |
| `just bump` | developer-only: mise upgrade --interactive → capture versions to feature catalog `tools` entries |
| `just capture` | developer-only: chezmoi re-add for known mutable paths (pi settings, mcp config) |
| `just update` | upgrade native packages, mise tools, and feature integrations |
| `just cleanup` | clean system (mole), project artifacts (kondo), and toolchain caches (go, cargo, uv, npm, pnpm, bun) |
| `just status` | show installation mode, source, OS, config, and tool locations |

## VCS — jj (not git)

This repo uses **jj**. Never use `git commit` or `git add`.

GPG signing is broken (nix-gpg removed). Always run jj with:

```bash
jj --config 'signing.behavior="drop"' <command>
```

Standard workflow:

```bash
jj --config 'signing.behavior="drop"' log -r @   # check current revision
jj --config 'signing.behavior="drop"' new -m "..."  # new revision if scope differs
jj --config 'signing.behavior="drop"' describe -m "..."  # update description
```

## Code rules

- No comments in code. If a comment feels necessary, refactor instead.
- English prose only. Non-Latin key symbols are allowed in keyboard mapping data.
- `kaizen.py` is the only orchestrator; do not add new Python files unless adding a `post_install.py` to a feature.
- Package names must be valid for their manager — verify before adding (e.g., `go-tools` does not exist in Homebrew).
- Prefer adding features over modifying `kaizen.py`.
- Put idempotent OS configuration in a feature's `post_install.py`; keep privileged or security-sensitive changes opt-in.

## External skills

Skills under `dotfiles/dot_agents/skills/` and `dotfiles/.agents/skills/` are immutable external dependencies. Never manually edit, reformat, patch, or add files inside their directories. Restore or update them only through the skill manager or exact upstream contents. Project dependency lock files are not versioned; upstream files inside external skills remain untouched.

Keep compatibility rules in `dotfiles/literal_AGENTS.md` and local review policy in `dotfiles/dot_agents/references/`. Keep custom workflows outside external skill directories.

## Adding a feature

1. Add a uniquely named section to the appropriate `features/*.toml` catalog.
2. Declare packages and inline tools there; specify `platforms`, `distributions`, and an explicit hook path only when needed.
3. The feature is discovered automatically; installation does not choose the running WM or start its service.
4. Set `archive = true` in its section to archive a feature; omission means active. Keep the section and dependencies in place when moving owned files to `.arhive/<name>/`. Optional `dotfiles` metadata lists repository-relative source paths for AI discovery, not runtime ownership rules.
5. Keep implementation-specific profiles in their app directories. Shared selectors, such as `dot_config/skhd/skhdrc` with one `.load`, choose a profile explicitly. Resolve selector references before archiving a selected profile; restoring files does not switch the selection.
