---
description: Complete an engineering task using only the research, implementation and review stages it needs.
---

Complete this task: $ARGUMENTS

Clarify only material ambiguities. Inspect the relevant implementation and project
instructions before choosing an approach.

Use the smallest useful workflow. Delegate independent research, design or review
only when it materially improves confidence. Use tools and agent names actually
available in the current session; do not assume a particular plugin API.

For substantial changes:

1. Establish the goal, constraints and observable acceptance criteria.
2. Inspect the affected code and consult official documentation when external semantics matter.
3. Choose the smallest coherent solution; compare alternatives only for contested decisions.
4. Implement and run focused checks.
5. Request independent implementation review when the risk justifies it.
6. Fix verified in-scope defects and recheck affected behavior.

Use `jj diff` in Jujutsu repositories and respect explicit revision scopes.
Do not create workflow report files unless requested. Stop for material scope
changes, missing permissions or architectural decisions requiring the user.

Report changes, checks actually run and unresolved limitations. Do not mark a
stage complete merely because a subagent returned a summary.
