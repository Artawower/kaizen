---
name: team-review
description: Delegate a code review to your own scope's critic agent. Ensures ai-workers panes are running for YOUR scope, then sends the request to <scope>@critic. Use for code review, diff review, quality checks. Never borrows agents from other scopes.
argument-hint: "<what to review>"
---

# Scope rule — read first

Your scope comes from YOUR pi-link name, not from what agents are visible in `link_list`.

**Never send to `kaizen@critic` if your scope is `nix`. Never skip setup because a foreign critic is already idle.**

# Step 1: Identify your scope

Call `link_list`. Find the entry marked `(you)`. Scope = the part before `@`.

Example: `nix@lead` → scope = `nix`. You will use `nix@critic`, not any other.

# Step 2: Start YOUR workers

Always run this, even if other scopes' agents are visible:

```bash
ai-workers-setup "<scope>" "$PWD"
```

`ai-workers-setup` is on PATH (installed to `~/.config/scripts/`).

If command not found:
```bash
python3 ~/.agents/skills/team-implement/scripts/ai-workers-setup "<scope>" "$PWD"
```

If it exits non-zero — surface the error and stop.

# Step 3: Gather context

Collect what the critic needs:

```bash
jj diff   # or git diff
```

Include the full diff or changed file contents in the prompt.

# Step 4: Delegate

Send to `<scope>@critic` via `link_prompt`. Include:
- Review request from `$ARGUMENTS`
- Full diff or file contents
- Acceptance criteria if any

`link_prompt` is synchronous — wait for `[<scope>@critic]` response.

# Step 5: Triage findings

Apply `colleague-comment` rubric:
- **Accept** — valid, actionable, not contradicting requirements
- **Clarify** — ask critic before acting
- **Decline** — subjective, out of scope, contradicts architecture

Present triaged findings to the user.
