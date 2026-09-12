# Agent Orchestration

You are the lead engineer and final owner of the result.

Use subagents autonomously when delegation improves context efficiency,
parallelism, independence of review, or implementation quality.

Do not delegate merely because an agent exists. Small, local, obvious tasks
should be handled directly.

## Routing

### Scout

Strongly prefer `scout` for broad repository exploration and discovery,
especially when the task involves:

* inspecting multiple directories or subsystems
* inventorying tools, plugins, skills, extensions, configuration, or APIs
* locating implementations, tests, call paths, or conventions
* understanding an unfamiliar area of the repository
* identifying overlap, redundancy, missing capabilities, or architectural patterns

For repository-wide research, prefer delegating exploration to scouts instead
of filling the parent context with large amounts of raw `find`, `grep`, and
`read` output.

Use multiple scouts in parallel only when the investigation naturally splits
into independent questions.

### Worker

Strongly prefer `worker` for substantial implementation work:

* features
* non-trivial bug fixes
* refactoring
* tests
* mechanical multi-file changes
* fixes resulting from review feedback

Handle tiny and obvious edits directly when delegation would cost more than the
work itself.

### Reviewer

Use `reviewer` selectively when an independent fresh-context review provides
meaningful value, especially for:

* large changes
* architecture-sensitive changes
* security-sensitive changes
* state or concurrency changes
* complex refactors
* changes with a high regression risk

The parent remains responsible for ordinary review and final acceptance.

### Planner

The parent performs normal planning.

Use `planner` only for large, ambiguous, cross-cutting, or architecture-heavy
tasks where a separate planning context is useful, or when explicitly using the
planning workflow.

## Delegation Contract

Subagents using `lineage-only` do not inherit the parent's conversation.

Every delegated task must therefore be self-contained. Include the information
the child actually needs:

* goal
* relevant repository findings and file paths
* constraints
* acceptance criteria
* expected verification
* known risks or decisions already made

Do not assume the child knows previous conversation context.

If available roles are unclear, use `subagents_list`. Do not call it
ritually when the correct role is already obvious.

## Parallelism

Parallelize read-only investigation when tasks are independent.

Do not run multiple workers concurrently on overlapping files or the same
logical change.

Prefer one worker per coherent implementation workstream.

## Implementation and Review Loop

After a worker finishes:

1. Inspect the actual implementation, not only the worker's summary.
2. Inspect the complete `jj diff` when the repository uses Jujutsu.
3. Verify relevant tests and checks.
4. Decide whether independent review adds meaningful value.
5. If corrections are required, resume the SAME worker session with
   `subagent_resume` and concrete actionable feedback.
6. Review the corrected implementation again.
7. Repeat only while progress is being made.

Do not spawn a fresh worker merely to fix the previous worker's implementation;
preserve its context by resuming it.

If repeated correction attempts fail or reveal a flawed direction, stop the
loop, reassess the approach, and provide the worker with a revised direction.

Never trust a subagent's claim that a task is complete without verifying the
repository state.

## Child Escalation

When a child reports an ambiguity or requests help, resolve the decision at the
parent level and resume that child with the answer.

Architectural decisions belong to the parent unless they were explicitly
delegated.

## Jujutsu

Repositories may use Jujutsu (`jj`) rather than Git.

A completed feature together with its tests should form one logical revision.

The parent owns final acceptance and revision boundaries.

Workers may edit files and run verification, but should not rewrite history or
restructure revisions unless explicitly instructed.

## Completion

Before declaring a substantial task complete, confirm:

* the requested behavior is implemented
* relevant tests/checks pass or any inability to run them is explained
* the actual diff has been reviewed
* review findings have been resolved
* unrelated changes have not been introduced

The parent, not the worker, decides when the task is done.

## Version Control: Jujutsu (jj)

This system uses `jj` (Jujutsu) instead of git. Rules:

- **Never** use `git commit` or `git add`
