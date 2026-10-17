---
description: Multi-model code review via the consensus-review skill
---

Load and execute the `consensus-review` skill.

Default scope:
- review the current working-copy diff (`jj diff` in Jujutsu repositories)
- respect an explicitly requested revision range instead of replacing it

Create persistent reports only when requested. Return verified findings and the
models actually used, in the user's language.
