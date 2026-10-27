---
name: jj
description: Jujutsu (jj) revision workflow. Use before creating, describing, squashing, splitting, rebasing or pushing jj revisions, and when translating Git instructions to jj.
---

# Jujutsu

The working copy is the revision `@`. Every jj command snapshots it, so there is no staging area and no separate commit step. Address revisions by change ID: it survives rewrites, while the commit ID changes.

## Non-interactive use

Pass `-m "<message>"` to `describe`, `new`, `commit`, `squash` and `split`, and pass filesets to `split`, `squash` and `restore`. Without them jj opens an editor or a diff TUI and the agent hangs. For `jj squash` into a described parent, `-u` keeps the destination message.

Resolve conflicts by editing the conflict markers in the files, then confirm with `jj st`.

After any rewrite (`squash`, `split`, `absorb`, `abandon`, `rebase`, `restore`), confirm the graph with `jj log`. `jj undo` reverts the last operation.

## Revision scope

Before the first file change, read the current revision:

```bash
jj log --no-graph -r @ -T 'change_id.short() ++ " | " ++ if(description, description.first_line(), "(empty)") ++ " | diff:" ++ if(self.empty(), "no", "yes") ++ "\n"'
```

| Description | Diff | Action |
| --- | --- | --- |
| empty | no | Work here; describe it after the first change. |
| empty | yes | Describe the existing work, or `jj new -m` for a different task. |
| set | any | Same task: continue. Different task: `jj new -m "<description>"` first. |

One revision holds one logical change. When the scope match is unclear, start a new revision; `jj squash` merges it back cheaply. Before finishing, make sure the description states what actually changed.

Read [references/descriptions.md](references/descriptions.md) when writing or refining a description.

## Rewriting history

| Goal | Command |
| --- | --- |
| Fold `@` into its parent | `jj squash -m "<message>"` |
| Move some files elsewhere | `jj squash --from <rev> --into <rev> <paths>` |
| Send hunks to the revisions that last touched those lines | `jj absorb` |
| Split one revision into several | read [references/split.md](references/split.md) |
| Drop a revision | `jj abandon <rev>` |
| Move a revision and its descendants | `jj rebase -s <rev> -o <destination>` |
| Restore files from another revision | `jj restore --from <rev> <paths>` |

## Bookmarks and push

Bookmarks stay in place when new revisions are added. Before pushing, point the bookmark at the intended revision with `jj bookmark set <name> -r <rev>`, which creates or moves it.

Push only when the user asks: `jj git push -b <name>`. Untracked bookmarks start tracking the remote automatically.
