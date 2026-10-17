---
name: link-msg
description: Explicitly route a task to a managed engineering colleague through pi-servitors. Use when the user asks to delegate via the link network.
---

# Link Message

Load the `pi-servitors` skill. Select the smallest suitable role: researcher-code
for broad investigation, coder for implementation or reviewer for review.

Provision that role and use the returned exact destination and Lead reply identity.
Send a self-contained task packet with a task ID, goal, constraints and acceptance
criteria. End the coordination turn after delivery and consume the callback.

Do not use guessed names, synchronous request tools, polling or terminal-backend
messaging. If the user explicitly names an unmanaged colleague, ask for an
appropriate direct communication setup rather than adopting that agent as a worker.
