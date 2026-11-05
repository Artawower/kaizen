---
defaults: standard
tracker:
  kind: file
  board_root: ./kanban
workspace:
  root: ~/symphony_workspaces/kaizen
  reuse_policy: refresh
agent:
  kind: codex
  max_cuncurrent_agent: 2
  stage_kinds:
    "In Progress": claude
    Verify: codex
    Document: agy
  fallback:
    - agy
server:
  host: 127.0.0.1
  port: 9999
---

You are working on {{ issue.identifier }}: {{ issue.title }}.
