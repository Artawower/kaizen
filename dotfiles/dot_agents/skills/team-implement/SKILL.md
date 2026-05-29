---
name: team-implement
description: Full feature development cycle with herdr-managed agent panes. Ensures an ai-workers tab exists with coder, researcher, and critic panes, then orchestrates implement-review loop via pi-link. Use when you want a persistent multi-agent workspace managed by herdr.
argument-hint: "<what to implement>"
---

# Task

$ARGUMENTS

# Phase 0: Self-Connect to pi-link

Call `link_list`.

**Case A — "Not connected":**
Tell the user:
> "Please type `/link-connect` then `/link-name <project>@lead` in this terminal, then re-run."

Stop here and wait.

**Case B — Connected, but name has no `@`** (e.g. `t-a1b2`):
Tell the user:
> "Please type `/link-name <project>@lead` to identify yourself, then re-run."

Stop here and wait.

**Case C — Connected with a proper name** (contains `@`, marked `(you)`):
Extract scope: `kaizen@lead` → scope = `kaizen`. Continue.

> **Rule:** scope = the part before `@` in YOUR OWN name.
> Never use workers from a different scope, even if they appear idle in `link_list`.
> `study@coder` is NOT your worker if your scope is `tmp4`.

# Phase 1: Environment Check

```bash
echo $HERDR_ENV
```

If `HERDR_ENV=1` → herdr available. Otherwise note it and continue — Phase 2 will handle the fallback.

# Phase 2: Ensure YOUR Workers Are Ready

Your workers are: `<scope>@coder`, `<scope>@researcher`, `<scope>@critic`.

**This step is mandatory. Do not skip it even if other scopes' workers appear idle in `link_list`.**

```bash
ai-workers-setup "<scope>" "$PWD"
```

If not on PATH:
```bash
python3 ~/.agents/skills/team-implement/scripts/ai-workers-setup "<scope>" "$PWD"
```

**Reading output:**

| Line | Meaning |
|------|---------|
| `all agents already idle — nothing to do` | workers ready, continue |
| `missing agents: <scope>@coder, ...` | starting them now |
| `reusing stored panes` | correct panes reused, no new ones created |
| `<name> ready` | agent reached idle |

**On error** (exit non-zero):

| Error | Action |
|-------|--------|
| `No workspace found matching cwd` | open this project directory in herdr first |
| `Timeout waiting for <name>` | check the pane manually |
| `nested herdr is disabled` | add `nested_herdr = true` to `~/.config/herdr/config.toml`, reload |
| `No supported multiplexer detected` | run pi from inside herdr/zellij/tmux |

Stop and show the error to the user if script exits non-zero.

# Phase 3: Clarify the Task

Evaluate `$ARGUMENTS`. Identify ambiguities. Ask clarifying questions before writing any code.

# Phase 4: Research

Delegate to `<scope>@researcher` via `link_prompt`. Ask for:
- Relevant codebase structure, patterns, conventions
- Any external references needed

Then **wait** for the response — `link_prompt` is synchronous, you receive the result directly.

# Phase 5: Plan

Draft a minimal implementation plan with clear acceptance criteria.

Check jj revision matches the task scope. If not, create/describe a new one.

# Phase 6: Implement → Review Loop

**Maximum 3 iterations. You must complete this loop fully — do not stop early to tell the user "check the tab".**

## Each iteration:

**Step 1.** Send plan (or fix list) to `<scope>@coder` via `link_prompt`.
`link_prompt` is synchronous — wait for `[<scope>@coder]` response before continuing.

**Step 2.** After receiving coder's response, additionally confirm idle via herdr:

```bash
herdr agent wait "<scope>@coder" --status idle --timeout 300000
```

**Step 3.** Read full coder output:

```bash
herdr agent read "<scope>@coder" --source recent-unwrapped --lines 80
```

**Step 4.** Send to `<scope>@critic` via `link_prompt` for review.
Include: task context, acceptance criteria, list of changes, any skipped items with reasons.
Wait for `[<scope>@critic]` response.

**Step 5.** Confirm idle:

```bash
herdr agent wait "<scope>@critic" --status idle --timeout 120000
```

**Step 6.** Read critic output:

```bash
herdr agent read "<scope>@critic" --source recent-unwrapped --lines 80
```

**Step 7.** Triage findings (`colleague-comment` rubric):
- **Accept** — valid, actionable, not contradicting requirements
- **Clarify** — ask critic before acting
- **Decline** — subjective, out of scope, contradicts architecture

All findings resolved → exit loop.
Accepted findings remain → send fix list to coder, repeat from Step 1.

**After 3 iterations with unresolved items:** make the final call yourself, document reasoning, move on.

# Phase 7: Summary

Deliver to the user:
- What was implemented
- Key decisions
- Declined items and why
- Open questions
