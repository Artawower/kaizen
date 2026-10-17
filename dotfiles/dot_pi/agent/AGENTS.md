# Engineering orchestration

The current main Pi session is the Lead.

For substantial engineering tasks, use the `pi-servitors` skill.

The Lead owns:
- understanding the task
- deciding which workflow stages are useful
- architecture and high-level decisions
- resolving ambiguity and escalations
- final acceptance

The `pi-servitors` skill owns persistent worker orchestration.
Use `team_ensure_role` to provision workers and `link_send` for task delivery
and callbacks. Herdr owns terminal lifecycle, not worker communication.

Do not manually repurpose, rename, or adopt unrelated Herdr agents.

Small, obvious, local tasks may be handled directly without delegation.
