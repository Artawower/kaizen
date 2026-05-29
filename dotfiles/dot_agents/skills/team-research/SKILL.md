---
name: team-research
description: Delegate a research task to your team's researcher agent via pi-link. Ensures the ai-workers panes are running, then sends your request to <scope>@researcher and returns the result. Use when you need deep research, codebase exploration, or external reference lookup done by a dedicated agent with the research model.
argument-hint: "<what to research>"
---

# How the team system works

You are the lead agent (`<scope>@lead`). Your team runs in the `ai-workers` herdr tab:
- `<scope>@researcher` — research model, deep exploration
- `<scope>@coder` — coder model, implementation
- `<scope>@critic` — reviewer model, code review

Models are defined in `~/.config/kaizen/models.toml` and assigned per role at startup.

# Task

$ARGUMENTS

# Step 1: Identify your scope

Call `link_list`. Find the entry marked `(you)`. Extract scope from `<scope>@lead`.

> Rule: scope = part before `@`. Never use workers from a different scope.

# Step 2: Ensure researcher is running

```bash
python3 ./scripts/ai-workers-setup "<scope>" "$PWD"
```

If exit non-zero — surface the error to the user and stop.

# Step 3: Delegate to researcher

Send `$ARGUMENTS` to `<scope>@researcher` via `link_prompt`. Include:
- The exact research question from `$ARGUMENTS`
- Any relevant context from the current codebase or conversation

`link_prompt` is synchronous — wait for the `[<scope>@researcher]` response before continuing.

# Step 4: Return result

Present the researcher's findings directly to the user. Do not paraphrase — return the full response.
