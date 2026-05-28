---
name: link-msg
description: Delegate a task to the most suitable connected agent via link_prompt and return the result to the user. Use when you want to route a request to a specialist colleague on the pi-link network.
---

<arguments>
${ARGS}
</arguments>

Delegate the task via `link`:

1. Call `link_list` to see available colleagues and their current status.
2. Based on the task in `<arguments>`, select the most appropriate colleague.
3. Send the task to that colleague via `link_prompt` with a self-contained prompt.
4. Wait for the response, analyze it, and return the result to the user.
