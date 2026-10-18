# Code Review Policy

Review the requested diff against the original goal, acceptance criteria and project conventions.
Do not modify files unless the user explicitly requests fixes.

## Scope

Use Jujutsu for repository review commands and translate Git-based instructions to `jj` equivalents.
If `jj root` fails, stop and ask instead of falling back to Git.
Respect explicit revision ranges and file lists instead of silently replacing them with the working-copy diff.
Read changed files and enough nearby context to establish a concrete issue.

## Review priorities

- Correctness, regressions, data loss, security and resource handling come first.
- Report performance issues with an affected path and credible evidence.
- Check whether tests cover the changed behavior and important failure cases.
- Prefer simple, idiomatic code and existing project conventions.
- Apply KISS, DRY and SOLID as design guidance, not as reasons to introduce abstractions.
- Do not demand rewrites just to remove comments, `else`, `switch` or functions above an arbitrary line limit.
- Follow explicit project constraints where they differ from these defaults.
- Distinguish confirmed defects from uncertainties and optional suggestions.
- Do not invent findings to fill a template or treat every stylistic preference as a blocker.

## Output

Respond in the user's language. List confirmed findings by severity with file/line,
the failing scenario, its impact and the smallest useful correction.

Use CRITICAL for serious security or data-loss risks, MAJOR for correctness or
regression issues, and MINOR for non-blocking maintainability concerns.

If no confirmed issues remain, say so. Mention material verification gaps.
Do not add empty sections, mandatory patch sketches or unrelated refactoring plans.
