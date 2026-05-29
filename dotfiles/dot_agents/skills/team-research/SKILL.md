---
name: team-research
description: Delegate a research task to your own scope's researcher agent. Ensures ai-workers panes are running for YOUR scope, then sends the request to <scope>@researcher. Use for codebase exploration, external references, pattern lookup. Never borrows agents from other scopes.
argument-hint: "<what to research>"
---

# Scope rule — read first

Your scope comes from YOUR pi-link name, not from what agents are visible in `link_list`.

**Never send to `kaizen@researcher` if your scope is `nix`. Never skip setup because a foreign researcher is already idle.**

# Step 1: Identify your scope

Call `link_list`. Find the entry marked `(you)`. Scope = the part before `@`.

Example: `nix@lead` → scope = `nix`. You will use `nix@researcher`, not any other.

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

# Step 3: Delegate

Send `$ARGUMENTS` to `<scope>@researcher` via `link_prompt`. Include:
- The exact research question
- Relevant codebase context if needed

`link_prompt` is synchronous — wait for `[<scope>@researcher]` before continuing.

# Step 4: Return result

Present the researcher's findings in full to the user.
