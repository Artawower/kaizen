# Proving a binding claim

## Deployment and effective selection

Separate four questions: does an owned source exist, where does it deploy, which profile does the repository select, and what is running now? A missing package entry answers none of the first three.

For every investigated include, record the deployed target and the owned source that supplies it. Resolve source encoding with native queries: chezmoi attributes such as `dot_`, `private_`, `empty_`, `executable_` and `.tmpl` change the deployed name. An empty `empty_binds.kdl` supplies `binds.kdl`; empty content is not an absent source. Use `target-path` on a source and `source-path` on a destination, with the repository's actual source root. A missing-source claim needs the failed relevant-platform query and an inventory crosscheck, not a literal filename search. A negative query under macOS does not establish absence from Linux. Inspect ignore rules and repeat with relevant platform data in an isolated configuration/destination/state. If mapping cannot be established, report unresolved deployment rather than inventing an external provider. Never apply to the real home directory for an audit.

Use merged repository defaults and selectors to determine selected profiles. Inspect native automatic loading as well as explicit includes: plugin directories, literate source execution and shared mode maps can supply effective bindings. A later override can resolve an apparent collision. A repository-selected profile is not proof of live activation; report that distinction.

## Layout and Russian equivalence

Determine applicability per action rather than classifying the entire shortcut catalog as editor-only. Assess a window manager's equivalents to pane focus, movement, rotation and zoom individually, explaining semantic differences; application-workspace requirements do not become OS-workspace requirements. In a vertical-only selector, up/down requirements apply; an extra horizontal-letter alias for up is not a rightward-navigation defect when no horizontal action exists. Compare preferred keys for supported actions and establish which required action, if any, an extra alias displaces.

For a layout finding, establish this chain:

`required action and keys -> effective binding/context -> platform decoder -> translation -> actual action`

Record the concrete mismatch. Comments and filenames can suggest a question, but do not choose the decoder. A logical `j` for down can be correct next to a QWERTY comment. A logical `n` for down can be incorrect next to a Colemak comment. A global dispatch setting or `[KeyJ]` token needs platform-specific resolution, not inference from its spelling.

For physical handlers, translate inputs and emitted outputs under the configured layout. Physical `H/Y/N/U` can produce logical Colemak `h/j/k/l`; replacing those codes with `H/J/K/L` can break a correct mapping. Modifier and Shift behavior matter. Layout-independent physical interception can preserve Russian equivalence without Cyrillic strings in the config.

For logical handlers, inspect native language mapping, inherited defaults and explicit aliases before concluding that Russian commands are absent. Compare existing explicit aliases against their actual targets; a wrong target can be proved without speculating about the rest of the engine. Translate command input, not inserted text.

For translation tables, check data parity and execution scope separately: built-in commands, custom mappings, modifier chords, sequences, uppercase input and text insertion may take different paths. A table matching all characters proves table parity, not whole-app compliance. If support is unknown, state the exact scope and the evidence you tried. A documented rejection of Cyrillic input is unsupported capability, not a config defect.

## Collisions, commands and modes

Compare declarations in their effective mode and scope, then establish engine policy:

- Same chord, different actions: a conflicting declaration; rejection, override or multi-action behavior depends on the engine.
- Same chord, same action: redundancy unless a separate failure is demonstrated.
- Deliberate chaining: evaluate the resulting compound action rather than declaring a collision from repeated tokens.
- Ordered dispatch: distinguish a dead duplicate branch from a reachable branch with one redundant alternative. Text capture inside search mode is different from normal navigation.

Follow every shortcut command through continuations, referenced scripts and action definitions, including OS-level bindings outside the application-pane preferences. Record each active command's executable, options and expanded or structurally resolved paths, with a result or investigated limitation. Separate binding grammar, shell grammar and operational behavior. Passing `bash -n` does not prove that paths, flags or invoked executables are valid. Verify command options in documentation/source before running a service command, even when its name looks like help.

Resolve grammar questions through version-relevant lexer/parser rules or safe isolated probes before treating a service launch as necessary. Distinguish whitespace before the first command token from continuation inside the command body; physical line breaks alone do not establish either a defect or an inaccessible runtime question.

Use isolated stubs for execution checks. Attribute failure to the command and file actually reached; a parser loop that stops on the first file says nothing about later files. Capture each check's exit status instead of the last successful command in a shell block.

## Evidence and acceptance

Keep a concise claim record:

- Requirement and applicable context.
- Exact source locations, selected load chain and effective binding, with a short source excerpt or parsed value from that component.
- Decoder or engine semantics with relevant version/platform when needed.
- Observed or source-derived behavior, countercheck, and narrow verdict.
- Executed checks with exact commands, inputs, exit/results and artifacts; distinguish source inspection from execution.

Verify source facts before interpreting behavior. Reopen the cited source or parse its native data container: an explicit binding table disproves a no-mappings claim, and settings from a neighboring component prove nothing about this one. Preserve the source path with extracted facts so final synthesis can recheck their ownership. For absence claims, record what was queried and which encoded sources, inherited defaults or external APIs were checked.

Before accepting a defect, ask what would make the same evidence compliant and check that possibility. Before accepting a match, ask which contexts were not tested. A missing investigation step is work to do; an inaccessible engine question is a limitation to report. Apply this acceptance rule to worker output as well as your own conclusions.
