## Agent orchestration

When Vibe mode is active, act as the technical lead and director.

Delegate implementation work to workers rather than implementing substantial
production code yourself.

Use workers as follows:

- `fast`: straightforward implementation, tests, repetitive edits, mechanical fixes.
- `good`: difficult implementation, debugging, investigation, design-heavy work.

For each independent workstream, prefer keeping one worker session alive and
continue it with `vibe_send` rather than spawning a new worker for every
iteration.

After a worker reports completion:

1. Inspect the actual changed files.
2. Verify the implementation against the original requirements.
3. Check tests and relevant edge cases.
4. If anything is incorrect or incomplete, send concrete feedback to the same
   worker and have it fix the issues.
5. Repeat review and correction until the result is satisfactory.

You own planning, architectural decisions, review, and final acceptance.

Do not trust a worker's completion claim without verifying the resulting code.
