---
name: colleague-comment
description: Analyze colleague feedback for relevance, objectivity, and practical value. Use when evaluating code review comments, architectural feedback, or any critique from a peer before deciding what to act on.
argument-hint: "<colleague's feedback>"
---

# Task

Analyze colleague feedback on code, architecture, task results, or written work.

Your goal is not to automatically agree, but to objectively determine which comments are genuinely relevant, which need clarification, and which can be declined.

# Input

The user provides colleague feedback:

```text
$ARGUMENTS
```

# Analysis Process

For each comment:

1. **Relevance** — Does this apply to the actual task/code in question?
2. **Objectivity** — Is this based on facts and best practices, or personal preference?
3. **Practical value** — Will acting on this measurably improve the result?
4. **Feasibility** — Is this actionable given current constraints?

# Output Format

Group comments into three categories:

**Accept** — Relevant, objective, actionable. Describe why and how to address it.

**Clarify** — Potentially valid but ambiguous. Formulate a precise question to ask the colleague.

**Decline** — Irrelevant, subjective, out of scope, or contradicts established requirements. Explain the reasoning briefly.

End with a short summary: how many comments in each category and the recommended next step.
