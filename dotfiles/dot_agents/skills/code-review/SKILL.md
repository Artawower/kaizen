---
name: code-review
description: Reviews the current revision or an explicitly requested diff or jj revision range for correctness, regressions, security and maintainability. Use for code review, diff review or pre-commit validation.
---

# Code Review

Use this skill for review-only work.

## Canonical Review Rubric

Before reviewing, load the canonical reviewer policy:

- `../../references/code-reviewer.md`

Treat that file as the source of truth for:
- review rules
- severity model
- output format
- language behavior

## Scope

Unless the user specifies another scope, review the current revision. If the user gives a revision, range, bookmark or file list, use that scope instead.

| User says | Diff |
| --- | --- |
| nothing or `@` | `jj diff --from @- --to @` |
| `<change-id>` | `jj diff -r <change-id>` |
| `<a>..<b>` | `jj diff --from <a> --to <b>` |
| `[bookmark]` | `jj diff --from trunk() --to <bookmark>` |
| `last N` | `jj diff --from 'roots(ancestors(@, N))-' --to @` |

For a bracketed name, find the bookmark with `jj bookmark list`; if several match, ask which one. For a range of several revisions, list them first with `jj log -r '<from>::<to>'` and report the count.

Use `jj diff --summary` for the file list and `jj diff -- <file>` for one file.

If there is no diff, say so clearly and stop.

## Review Workflow

1. Determine the exact review scope.
2. Read only the changed files and the minimum nearby context needed to judge correctness.
3. Apply the rubric from `../../references/code-reviewer.md` strictly.
4. Focus on correctness and material maintainability risks, not stylistic quotas.
5. Call out missing tests and edge cases explicitly.
6. For multi-revision ranges, keep one report and attribute a finding to a revision only when it clearly belongs to one.
7. Respond in the same language as the user's request.

## Constraints

- Do not implement fixes unless the user explicitly asks for them.
- Do not review unrelated files.
- Prefer precise, actionable findings over broad opinions.
- Merge duplicate findings.

## Output

Follow the output structure defined in `../../references/code-reviewer.md`.
