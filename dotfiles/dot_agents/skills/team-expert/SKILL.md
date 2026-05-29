---
name: team-expert
description: Escalate a decision or architectural question to your team's expert agent via pi-link. Ensures the ai-workers panes are running, then sends your question to <scope>@expert and returns the verdict. Use when you need an authoritative architectural decision, a second opinion on a complex design, or expert arbitration between competing approaches.
argument-hint: "<question or decision to escalate>"
---

# How the team system works

You are the lead agent (`<scope>@lead`). Your team runs in the `ai-workers` herdr tab:
- `<scope>@expert` — default model, architectural authority
- `<scope>@coder` — coder model, implementation
- `<scope>@researcher` — research model, deep exploration
- `<scope>@critic` — reviewer model, code review

Models are defined in `~/.config/kaizen/models.toml` and assigned per role at startup.

> Note: `team-implement` ensures `coder/researcher/critic`. The `expert` role is separate and
> may not be in the ai-workers tab — it is typically a persistent named session started manually.

# Task

$ARGUMENTS

# Step 1: Identify your scope

Call `link_list`. Find the entry marked `(you)`. Extract scope from `<scope>@lead`.

Check if `<scope>@expert` appears in `link_list`:
- **Present** → proceed to Step 3
- **Absent** → tell the user: "Please start `pi-link <scope>@expert` in a terminal. Then re-run."  
  Stop and wait.

# Step 2: (if needed) Ensure ai-workers tab for other roles

If you also need coder/researcher/critic alongside expert:

```bash
python3 ./scripts/ai-workers-setup "<scope>" "$PWD"
```

# Step 3: Delegate to expert

Send to `<scope>@expert` via `link_prompt`. Include:
- The exact question from `$ARGUMENTS`
- Relevant context: current architecture, constraints, prior decisions
- Any options already considered and their tradeoffs

`link_prompt` is synchronous — wait for the `[<scope>@expert]` response.

# Step 4: Return verdict

Present the expert's decision directly to the user. The expert's verdict is final — do not override it.
