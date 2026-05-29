---
name: team-expert
description: Delegate deep domain analysis, architecture planning, or complex decisions to your own scope's expert agent (claude-opus). Ensures the expert is running for YOUR scope. Use for architectural decisions, multi-step planning, tradeoff evaluation, domain modeling. Never borrows agents from other scopes.
argument-hint: "<question, plan request, or domain to analyze>"
---

# Scope rule — read first

Your scope comes from YOUR pi-link name, not from what agents are visible in `link_list`.

**Never send to `kaizen@expert` if your scope is `nix`. Never skip setup because a foreign expert is already idle.**

# Expert role

The expert runs on `models.expert` (`claude-opus`) — optimized for:
- Deep domain modeling and concept mapping
- Multi-step planning with dependency analysis
- Architectural decisions with explicit tradeoff reasoning
- Breaking ambiguous requirements into concrete specs

**Not for:** writing code (→ `team-implement`), quick lookups (→ `team-research`), code review (→ `team-review`).

# Step 1: Identify your scope

Call `link_list`. Find the entry marked `(you)`. Scope = the part before `@`.

Example: `nix@lead` → scope = `nix`. You will use `nix@expert`, not any other.

# Step 2: Start YOUR expert

Check if `<scope>@expert` is in `link_list` and idle:

**Yes** → proceed to Step 3.

**No** → run:

```bash
ai-workers-setup "<scope>" "$PWD"
```

`ai-workers-setup` is on PATH (installed to `~/.config/scripts/`).

If command not found:
```bash
python3 ~/.agents/skills/team-implement/scripts/ai-workers-setup "<scope>" "$PWD"
```

> Note: `ai-workers-setup` creates coder/researcher/critic. The expert pane is separate.
> If the expert is still absent after setup, tell the user to run:
> `pi-link <scope>@expert --model anthropic/claude-opus-4-8`

# Step 3: Gather context

Before delegating, collect what the expert needs:
- Relevant codebase structure (files, modules, interfaces)
- Existing architectural decisions and constraints
- What has already been considered and why

Quality of the expert's output scales directly with context depth.

# Step 4: Delegate

Send to `<scope>@expert` via `link_prompt`. Structure the prompt:

```
## Context
<codebase structure, existing decisions, constraints>

## Goal
<what needs to be planned or decided>

## Already considered
<options evaluated, with reasons accepted/rejected>

## Expected output
<plan / architecture doc / decision + rationale / task breakdown>
```

`link_prompt` is synchronous — wait for `[<scope>@expert]` response.

# Step 5: Act on the result

- **Plan** → confirm with user, pass to `<scope>@coder` via `team-implement`
- **Architectural decision** → record it (`jj desc` / docs), then proceed
- **Domain breakdown** → use as foundation for `team-research` or `team-implement`

The expert's decisions are authoritative. Do not override them silently.
