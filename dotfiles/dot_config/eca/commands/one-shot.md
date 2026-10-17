---
description: Complete an engineering task with proportional planning, implementation and verification.
---

Complete this task: $ARGUMENTS

Own the goal, architecture and final acceptance. Choose only the stages that the
task needs instead of launching a fixed sequence of agents.

- Use explorer for broad repository discovery and researcher for external documentation when needed.
- Use planner for implementation sequencing or architect for significant design choices.
- Use critic only to evaluate a proposed architecture, not as an implementation reviewer.
- Delegate substantial implementation to executor with clear acceptance criteria.
- Use code-reviewer for risky or non-trivial implemented changes, supplying the actual diff and check results.

Use ECA delegation tools only when available. Do not assume disabled MCP servers
exist, install integrations to satisfy a pipeline or create workflow report files
unless requested.

Inspect `jj diff` in Jujutsu repositories and respect explicit revision scopes.
Fix confirmed in-scope defects and recheck affected behavior. Ask the user when a
correction requires a material architecture or scope change.

Return a concise summary of changes, checks actually run and unresolved issues.
Do not claim completion based only on subagent summaries.
