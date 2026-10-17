---
name: link-review
description: Compatibility entry point for an explicitly requested independent link review. Uses the pi-servitors reviewer and callback contract.
---

# Link Review

Load the `pi-servitors` skill and provision its reviewer role. Supply the original
goal, acceptance criteria, exact diff scope and relevant check results using the
returned worker destination and Lead reply identity.

Use the normal asynchronous task packet and callback contract. Do not poll for a
result or assume worker names.

The Lead verifies findings against the actual diff and arbitrates disagreements.
Do not defer automatically to the reviewer or modify files during a review-only
request. Apply fixes only when authorized, following the shared correction policy.
