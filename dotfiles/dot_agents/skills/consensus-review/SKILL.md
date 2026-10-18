---
name: consensus-review
description: Runs independent multi-model reviews of a requested diff, verifies findings and merges duplicates. Use when the user explicitly asks for multiple independent opinions rather than a normal single review.
---

# Consensus Review

Use `../../references/code-reviewer.md` as the shared review policy.

## Scope and reviewers

Determine the exact requested diff. In Jujutsu repositories, use `jj diff` or the
requested revision range. Do not substitute a Git working-copy diff for a jj revision.
Stop if the requested diff is empty.

Discover available authenticated models and delegation tools instead of assuming
that an MCP bridge or a particular model version exists. Choose two or three
independent reviewers, preferably across model families, using exact available
provider/model IDs. Respect the active orchestration policy.

If fewer than two reviewers are available, disclose that limitation rather than
claiming consensus. Do not install providers or change credentials for the review.

## Workflow

1. Send the same task, acceptance criteria and diff scope to each reviewer independently.
2. Collect their results without showing one review to the other reviewers.
3. Verify proposed findings against the actual code.
4. Merge duplicates and reject unsupported claims or stylistic preferences.
5. Return the models used, confirmed issues, material disagreements and verification gaps.

Respond in the user's language. Create persistent report files only when requested,
using names derived from the models actually used rather than historical version labels.
