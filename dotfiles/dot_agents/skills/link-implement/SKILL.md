---
name: link-implement
description: Compatibility entry point for an explicitly requested link-implement workflow. Use pi-servitors for normal engineering delegation.
---

# Link Implementation

Load the `pi-servitors` skill and use its provisioning, task packet and callback
contract for the requested implementation.

Choose only the roles the task needs. Do not assume worker names or require a
pre-existing full team. Do not use legacy synchronous messaging or invent a
separate retry loop. The Lead owns architecture, revision scope and acceptance.

If provisioning or communication is unavailable, report the limitation and stop
delegation rather than switching to terminal-backend messages.
