---
name: link-review
description: Request a code review from an independent reviewer agent via link_prompt, then analyze and act on the findings. Use when you want an external perspective on recent changes before committing or merging.
argument-hint: "<what to review>"
---

Send the review request to the reviewer agent via `link_prompt`, passing the arguments:

<arguments>
${ARGS}
</arguments>

After receiving the review:

1. Analyze the findings carefully.
2. Separate blockers from suggestions.
3. Apply comments you consider valid and relevant.
4. Send a follow-up to the reviewer: share the changes made and explain which comments you skipped and why. Reach consensus on the skipped items.
5. Maximum 5 rounds of back-and-forth. If no consensus after 5 rounds, defer to the reviewer's judgment — they have domain expertise.
