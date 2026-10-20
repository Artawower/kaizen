---
name: keybindings-healthcheck
description: Read-only audit of keyboard shortcuts, layouts, Russian aliases, commands and configuration paths. Supports full-repository and focused audits.
---

# Keybindings Healthcheck

Audit whether configured keyboard shortcuts implement their intended actions in the effective application context.

Detect real defects without reporting unsupported assumptions, harmless differences or unverified suspicions.

Optimize for both **precision** (avoiding false positives) and **recall** (finding actual defects).

Investigate autonomously, verify conclusions and account for every relevant configuration entry before completing the audit.

## Rules

- Read repository guidance and `config.example.toml` in full.
- Resolve `jj root` and record the initial revision and working-tree state, disabling signing as required by repository guidance.
- Keep the audit read-only. Store notes and isolated fixtures outside the repository.
- Never execute commands extracted from configuration directly.
- Use safe parsing, stubs or isolated probes for potentially state-changing checks.
- Derive requirements from the current contract, not previous audits or assumed conventions.
- Distinguish source declarations, effective configuration and observed runtime behavior.
- Do not modify configurations, services or running applications.

## Scope

Accept an optional file, directory or behavioral question.

### Focused audit

When a scope is provided:

1. Resolve the target relative to `jj root`.
2. Read its entry point and follow dependencies affecting the requested behavior.
3. Include relevant loaders, profiles, imports, defaults and overrides.
4. Check all applicable dimensions unless the request explicitly narrows them.
5. Do not investigate unrelated components.

For behavior-only requests, locate the relevant configuration through targeted searches.

If the target is missing or ambiguous, attempt to resolve it before requesting clarification.

### Full audit

Without a scope, audit the owned, nonarchived repository.

Run:

```sh
sh <skill-directory>/scripts/discover.sh <absolute-repository-root>
```

Read `summary.txt`, verify `READY` and inspect `candidates.txt`.

Use [discovery.md](references/discovery.md) when interpreting discovery artifacts, symlinks or negative search results.

Group discovered sources by application or interactive component, including platform-specific and executable configurations.

Derive groups from actual source references rather than a predefined application list.

Before completion, reconcile `inventory.txt`, `remainder.txt` and `symlinks.txt`.

Exclude `.arhive/` and external dependency contents, including through symlinks. Investigate active references to excluded sources without opening their contents.

An archived configuration does not deactivate an otherwise active consumer.

## Requirements

Establish expected behavior before evaluating its implementation.

Use the following sources in order of authority:

1. Explicit user instructions.
2. Repository shortcut contract and applicable preferences.
3. Documented application-specific configuration intent.
4. Application semantics needed to interpret the above.

Distinguish:

- **Requirement:** Explicitly established expected behavior.
- **Preference:** Desired behavior that permits documented adaptations.
- **Implementation:** Actual configuration and effective behavior.
- **Inference:** A plausible interpretation without authoritative support.

Never promote an inference into a requirement.

Apply global requirements wherever the contract covers the application and context. Do not generalize application-specific requirements.

Application support for an action does not independently establish that the action must have a shortcut.

### Action equivalence

Compare semantic actions in equivalent input contexts, not merely key names.

Account for:

- Native leaders, modes and modifiers.
- Native defaults and inherited keymaps.
- Conditional loading, profiles and overrides.
- Intentional command chaining and fallback behavior.
- Differences between moving focus, moving a pane and moving its contents.
- Physical keys, characters, keyboard layouts and terminal encoding.

Additional bindings are allowed unless they interfere with required actions.

Do not require explicit mappings when native behavior already satisfies the contract.

Do not invent requirements for unsupported application capabilities.

### Russian aliases

Verify Russian-layout equivalence where the contract requires it.

Determine how the application interprets input:

- Physical key positions.
- Layout-dependent characters.
- Key symbols and modifiers.
- Terminal escape sequences.
- Application-native translation or aliases.

A missing explicit Russian alias is not a defect when effective behavior is already equivalent.

Do not infer broken navigation solely from missing alias declarations.

## Exhaustive coverage

**Completeness of inspection and confidence in conclusions are independent requirements.**

Before evaluating suspected defects, enumerate all relevant configuration entries within the declared scope.

For each applicable binding, inspect:

- Key syntax, modifiers, modes and input contexts.
- Command boundaries and shell syntax.
- Executable names and command-line options.
- Referenced paths, variables and expansions.
- Aliases, conflicts, defaults and overrides.

Follow multiline definitions, sourced files and conditional configuration where they affect the inspected behavior.

### Command validation

Inspect every applicable command, including commands attached to otherwise valid shortcuts.

Check:

1. Correct separation between binding declarations and executable commands.
2. Valid shell syntax and command structure.
3. Executable identity and availability in the intended environment.
4. Command-line flags against version-relevant documentation or executable help.
5. Referenced scripts and their expected locations.
6. Environment-variable and home-directory expansion.
7. Path construction, including accidental concatenation of directory prefixes.
8. Relevant command dependencies and invocation context.

Do not assume a command is valid merely because its binding syntax is valid.

Detect malformed command prefixes that resemble accidentally embedded shortcut declarations.

For paths, distinguish syntactically suspicious construction from demonstrated invalidity. Repeated separators alone do not establish a defect.

Do not assume an executable or file is missing from the target system merely because it is absent from the inspection environment.

An independently invalid command can be a defect even when the shortcut itself works as intended.

### Coverage tracking

Maintain an internal inventory of applicable entries.

For each entry, record:

- Source file and location.
- Relevant action or command.
- Applicable validation dimensions.
- Inspection result: `checked`, `defect`, `unresolved` or `not applicable`.
- Supporting evidence or reason for uncertainty.

Every discovered applicable binding, command and path must be accounted for.

Do not silently skip entries that appear correct.

A focused audit with explicitly restricted dimensions must cover those dimensions for every applicable entry, without expanding into unrelated checks.

A component cannot be marked complete while applicable entries remain unchecked.

The final report may omit successful checks, but the internal inventory must establish coverage.

## Evidence standard

Separate four evidence levels:

| Level | Establishes |
|---|---|
| Source | A declaration exists in an inspected file. |
| Effective configuration | The declaration applies after loading, selection and overrides. |
| Engine semantics | The application interprets the configuration in a documented way. |
| Runtime observation | Actual behavior is demonstrated in a specified environment. |

Use the strongest available evidence appropriate to the claim.

Static analysis is sufficient when the effective configuration and documented semantics determine the result.

Runtime testing is not universally required.

A successful syntax check proves syntax validity, not necessarily correct behavior.

A failed probe proves only what it actually tested. Never generalize its result to unrelated files, platforms or profiles.

Record version, platform and input context whenever they materially affect a conclusion.

### Confirming defects

Treat every suspected defect as a hypothesis.

A **Defect** requires either of the following.

**Behavioral mismatch:**

1. An established requirement and its source.
2. Proof that the requirement applies to the examined context.
3. Evidence of effective configuration or actual behavior.
4. A concrete mismatch between expected and actual behavior.
5. Resolution of plausible non-defective explanations.

**Invalid configuration:**

A demonstrably invalid command, binding, reference or configuration construct in an applicable configuration, supported by relevant parser, engine or environment evidence.

Before accepting a defect:

- Check applicable defaults, modes, selectors and overrides.
- Consider intentional adaptations and command chaining.
- Identify the strongest plausible non-defective explanation.
- Resolve contradictions between the finding and its supporting evidence.
- Verify that cited paths and actions belong to the examined component.

Not finding a counterexample does not itself prove a defect.

If material uncertainty remains, classify the investigated question as `Unresolved`.

### Negative evidence

Failure to find a declaration is not proof that effective behavior is absent.

Before asserting that a shortcut, alias, command or file is missing, establish a sufficiently complete search boundary.

Consider applicable:

- Includes and generated definitions.
- Conditional loading and selected profiles.
- Inherited mappings and native defaults.
- Plugins and dynamic registration.
- Layout translation and input interception.

Investigate alternatives supported by the actual application architecture, not arbitrary hypothetical mechanisms.

If relevant evidence cannot be inspected, record the exact limitation instead of guessing.

## Investigation workflow

Read [evidence.md](references/evidence.md) before closing the first component. Apply its source-fact and behavior checks without weakening the evidence standard.

Maintain one compact temporary work note outside the repository.

For each component, track:

- Source paths and effective loading chain.
- Platform, profile and input contexts.
- Applicable requirements.
- Inventory and inspection coverage.
- Evidence, findings and unresolved questions.
- State: `todo`, `inspecting`, `done`, `excluded` or `blocked`.

Investigate one component at a time.

1. **Discover** — Enumerate relevant bindings, commands, paths and dependencies.
2. **Trace** — Establish loaders, imports, selectors, defaults and overrides.
3. **Interpret** — Determine supported actions and applicable requirements.
4. **Inspect** — Validate every applicable entry and requested dimension.
5. **Verify** — Resolve suspected problems using source inspection, documentation, parsing or isolated probes.
6. **Challenge** — Test plausible non-defective explanations for each suspected defect.
7. **Reconcile** — Compare inspected entries against the inventory and resolve omissions.
8. **Close** — Record findings, limitations and coverage before moving to another component.

Choose the cheapest decisive verification method.

Do not stop investigating a component merely because several defects have already been found.

Do not repeatedly investigate already verified entries without a concrete reason.

Newly discovered owned dependencies must be added to the work note.

If a relevant owned source remains unread, investigate it before declaring the corresponding behavior unresolved.

Start with a small component to calibrate the investigation. Preserve completed results before expanding to the next component.

## Classification

Classify individual requirements and behaviors, not entire applications by implication.

| Result | Meaning |
|---|---|
| Matches | Evidence establishes required behavior within the examined context. |
| Defect | A concrete failure satisfies the evidence standard. |
| Redundancy | Duplicate behavior without demonstrated failure. |
| Unsupported | Engine evidence establishes a capability limitation. |
| Unresolved | A specific investigated behavior remains undetermined. |
| Not applicable | The requirement does not apply to the examined context. |

Classification rules:

- Suspicious syntax is not automatically incorrect.
- Unusual mappings are not automatically defects.
- Different bindings across different contexts are not automatically collisions.
- Missing explicit aliases do not imply broken layout support.
- Redundancy is not automatically a defect.
- One unresolved question does not invalidate independent findings.
- Unread entries remain unfinished, not `Unresolved`.
- Do not classify behavior as `Matches` beyond what the evidence establishes.
- Do not promote uncertainty to `Defect` merely to complete the audit.

Keep coverage status separate from behavioral classification.

## Recovery

Choose investigation methods autonomously.

When a method fails:

1. Record the attempted operation and actual result.
2. Identify what remains unproven.
3. Try another relevant read-only method when available.
4. Preserve any remaining uncertainty.
5. Continue independent checks.

Ask the user only when intent is materially ambiguous or further investigation requires permission for side effects.

At each component boundary, record:

- Established facts.
- Potential counterexamples.
- Remaining unchecked entries.
- Next concrete operation.

After context compaction, resume from the work note rather than rediscovering completed components.

## Completion criteria

The audit is complete only when:

1. Every applicable binding, command and path within scope has been inspected.
2. Relevant owned loading chains and dependencies are accounted for.
3. Every reported defect satisfies the evidence standard.
4. Investigated uncertainties have precise boundaries.
5. The internal inventory contains no silently omitted entries.
6. Final classifications agree with the supporting evidence.

For a focused audit, reconcile the selected target, applicable dimensions and relevant dependencies.

For a full audit, reconcile discovery artifacts against inspected components and justified exclusions.

Before finishing:

- Reopen cited source facts or repeat cheap decisive checks.
- Recheck each defect against its strongest plausible counterexample.
- Verify the exact component, file, action and context.
- Confirm that command and path checks cover every applicable entry.
- Distinguish source completeness from runtime verification.
- Compare the repository state with the initial baseline and disclose unexpected changes.

If the investigation is interrupted or access is blocked, preserve an incomplete checkpoint with the exact remaining work.

Never describe incomplete coverage as a completed audit.

## Final report

Read [report.md](references/report.md) after the investigation is complete.

Present a concise, evidence-based report containing:

- Audited scope and relevant environments.
- Inspection coverage.
- Confirmed defects.
- Redundancies and unresolved questions separately.
- Validation limitations.
- Unexpected repository-state changes.

For every defect, include:

1. Affected action, command or path.
2. Expected behavior or validity requirement.
3. Actual behavior and decisive evidence.
4. Relevant file paths and line numbers.
5. Verification method.

For unresolved findings, state the exact unknown and what evidence would resolve it.

Do not inflate the defect count with recommendations, suspicious patterns or unsupported interpretations.

Do not claim broader coverage or stronger verification than was established.

**The goal is to find all demonstrable defects within scope while reporting no unsubstantiated defects.**
