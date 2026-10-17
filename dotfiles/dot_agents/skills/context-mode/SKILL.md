---
name: context-mode
description: Optional indexed analysis of very large logs, datasets or documentation using an enabled and healthy context-mode MCP server. Use when the user asks for context-mode or repeated searches benefit from indexing; not for ordinary file reads, small commands or routine tests.
---

# Context Mode

Context-mode is an optional output-processing backend, not a replacement for all tools.
Native `read`, shell commands and Pi codemode are the default for ordinary work.

## Availability

Use context-mode only if its tools are already available and working.
If the server is disabled, absent or fails because of a runtime dependency, report
that limitation once and continue with native tools. Do not repeatedly retry it,
install packages or rebuild native modules unless the user requests a repair.

Do not assume Claude Code hooks, automatic subagent routing or browser tools exist
in another host. Follow the host's actual tool schemas and orchestration policy.

## Appropriate uses

- Index a large document that needs several independent searches.
- Filter large logs or structured datasets before returning a compact result.
- Process large tool output from a saved file without repeating it in context.

For small outputs or a single targeted lookup, use the simpler native tool.
For external documentation, use authoritative sources regardless of transport.
For files that will be edited, read their relevant content with the normal read tool.

## Output discipline

- Print the requested findings, exact evidence and meaningful failures.
- Save large raw outputs outside the repository when possible.
- Pass file paths to indexing tools rather than sending the same large content twice.
- Batch related search queries and scope them to the relevant indexed source.
- Use file-output parameters only when the actual tool schema supports them.
- Do not run concurrent actions against a shared browser session.
- Do not call arbitrary code execution a security sandbox without verified isolation.
- Preserve project VCS and permission rules; this skill grants no extra permissions.

Native alternatives include shell redirection with focused filtering and codemode
scripts that return only the useful parts of MCP results. Do not claim measured
context savings, speedups or equivalence without a relevant comparison.
