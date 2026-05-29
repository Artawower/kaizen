---
name: team-review
description: Delegate a code review to your team's critic agent via pi-link. Ensures the ai-workers panes are running, then sends your request to <scope>@critic and returns the review. Use when you want an independent code review, diff review, quality check, or pre-commit validation from a dedicated reviewer agent.
argument-hint: "<what to review — description or diff>"
---

# How the team system works

You are the lead agent (`<scope>@lead`). Your team runs in the `ai-workers` herdr tab:
- `<scope>@critic` — reviewer model, code review and quality checks
- `<scope>@coder` — coder model, implementation
- `<scope>@researcher` — research model, deep exploration

Models are defined in `~/.config/kaizen/models.toml` and assigned per role at startup.

# Task

$ARGUMENTS

# Step 1: Identify your scope

Call `link_list`. Find the entry marked `(you)`. Extract scope from `<scope>@lead`.

> Rule: scope = part before `@`. Never use workers from a different scope.

# Step 2: Ensure critic is running

```bash
python3 ./scripts/ai-workers-setup "<scope>" "$PWD"
```

If exit non-zero — surface the error to the user and stop.

# Step 3: Gather context

If `$ARGUMENTS` references a diff or files, collect the relevant content:

```bash
jj diff          # or git diff, depending on the repo
```

Include file contents and diff in the prompt to the critic.

# Step 4: Delegate to critic

Send to `<scope>@critic` via `link_prompt`. Include:
- The review request from `$ARGUMENTS`
- Full diff or file contents
- Acceptance criteria or focus areas if mentioned

`link_prompt` is synchronous — wait for the `[<scope>@critic]` response.

# Step 5: Triage and return

Apply the `colleague-comment` rubric to the findings:
- **Accept** — valid, actionable, not contradicting requirements
- **Clarify** — ask critic before acting
- **Decline** — subjective, out of scope, contradicts established architecture

Present the triaged findings to the user.
