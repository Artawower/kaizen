---
name: code-review
description: Reviews the current revision or an explicitly requested diff for correctness, regressions, security and maintainability. Use for code review, diff review or pre-commit validation.
---

# Code Review

Use this skill for review-only work.

## Canonical Review Rubric

Before reviewing, load the canonical reviewer policy:

- `references/code-reviewer.md`

Treat that file as the source of truth for:
- review rules
- severity model
- output format
- language behavior

## Default Scope

Unless the user specifies another scope, review the current working-copy diff.
In a Jujutsu repository, use `jj diff --summary` and `jj diff -- <file>`.
Otherwise use `git diff HEAD --name-only` and `git diff HEAD -- <file>`.

If the user gives a commit, branch, file list, or patch range, use that scope instead.

If there is no diff, say so clearly and stop.

## Review Workflow

1. Determine the exact review scope.
2. Read only the changed files and the minimum nearby context needed to judge correctness.
3. Apply the rubric from `references/code-reviewer.md` strictly.
4. Focus on correctness and material maintainability risks, not stylistic quotas.
5. Call out missing tests and edge cases explicitly.
6. Respond in the same language as the user's request.

## Constraints

- Do not implement fixes unless the user explicitly asks for them.
- Do not review unrelated files.
- Prefer precise, actionable findings over broad opinions.
- Merge duplicate findings.

## Output

Follow the output structure defined in `references/code-reviewer.md`.
