---
name: vitest
description: Plan and write Vitest tests for changed code. Analyses git diff, checks existing tests, produces a concrete test plan using flat test structure (no describe/it blocks). Use when adding tests for new/changed code, improving Vitest coverage, or asking what to test after a change.
---

# Vitest Test Planning

## Trigger

Use this skill when the user asks to write or plan tests for code changes visible in `git diff`.

## Conventions (non-negotiable)

- Framework: **Vitest**
- Structure: **flat** — use `test('EntityName does X', ...)` only. No `describe`, no `it`.
- Method: **black-box** — test only via public signatures; never expose internals or make private things public for the sake of testing.
- Never modify implementation to make it testable.

## Process

1. Run `git diff HEAD` (or use arguments if provided) to identify changed code.
2. Read changed files to understand public interfaces.
3. Check existing tests to avoid duplication and understand current coverage.
4. Produce a test plan with concrete `test(...)` names and what each asserts.

## Test plan format

```
## Test plan: <filename or feature>

### New tests
- test('UserService creates a user with valid data') → asserts returned user has correct fields
- test('UserService throws on duplicate email') → expects specific error type/message
- test('UserService.getById returns null for unknown id') → edge case

### Existing tests to update
- test('...') → reason for update

### Coverage gaps found (no action required from AI)
- ...
```

## Quality criteria

- Every test must be purposeful — no coverage for coverage's sake.
- Each test asserts one clear behaviour.
- Edge cases (null, empty, boundary values, error paths) must be included where meaningful.

## Output

Respond in the user's language.
