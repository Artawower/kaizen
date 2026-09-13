---
name: swarm
description: Orchestrate substantial engineering work with persistent Herdr role agents. The current Pi session is the Lead and chooses the smallest useful workflow; pi-herdr manages role sessions and correction loops.
---

# Swarm engineering workflow

The current Pi session is the Lead.

Use pi-herdr for managed agent and layout operations.

Agent models, thinking levels, tools, permissions, and role behavior are defined
by pi-open-agents profiles in:

    ~/.pi/agent/agents/

Available managed roles:

- `coder`
- `reviewer`
- `researcher-code`

There is no planner role.

Planning, architecture, routing, arbitration, and final acceptance belong to
the Lead.

Do not duplicate role configuration in this skill.

## Core principle

Choose the smallest workflow likely to produce a correct result with the lowest
total cost.

Optimize for:

1. correctness
2. total tokens per accepted implementation
3. minimal duplicate exploration
4. minimal model calls
5. minimal orchestration overhead

Do not invoke a role merely because it exists.

## Responsibilities

### Lead

The Lead owns semantic decisions:

- understand the task
- decide whether delegation is useful
- choose useful workflow stages
- plan at the appropriate level
- make architectural decisions
- decide whether broad research is worthwhile
- decide whether independent review is worthwhile
- resolve ambiguity
- arbitrate repeated review failures
- perform final acceptance

The Lead should not duplicate routine work already delegated to another role.

### coder

The coder owns:

- local implementation discovery
- directly relevant source inspection
- nearby convention inspection
- relevant test inspection
- implementation
- focused deterministic verification
- corrections requested by Lead or reviewer

Routine implementation exploration belongs to coder, not Lead.

### researcher-code

The researcher performs broad read-only repository investigation when separating
exploration from implementation is likely to save context or improve focus.

### reviewer

The reviewer independently inspects the implementation and returns a blocking
verdict.

Reviewer is not an orchestrator.

Reviewer must not:

- delegate to other agents
- invoke subagents
- modify repository files

## Workflow selection

Stages are optional.

Typical workflows:

    Lead -> coder -> Lead

    Lead -> coder -> reviewer -> Lead

    Lead -> researcher-code -> Lead -> coder -> Lead

    Lead -> researcher-code -> Lead -> coder -> reviewer -> Lead

For investigation-only requests:

    Lead -> researcher-code -> Lead

Small obvious tasks may be handled directly by Lead.

### coder

Use coder when delegated implementation is useful.

Do not make Lead inspect implementation in detail first merely to explain the
same implementation to coder.

### researcher-code

Use researcher-code when exploration is broad enough to justify a separate
context.

Examples:

- unfamiliar subsystem mapping
- repository-wide dependency discovery
- comparing several existing implementations
- conventions distributed across many files
- cross-cutting architectural investigation
- investigation requiring repository evidence plus external documentation
- comparing the current implementation with established external approaches

Do not use researcher-code for one or two simple file or symbol lookups.

After research completes, control returns to Lead.

The researcher result is the primary evidence bundle for the delegated
investigation.

Lead should interpret that evidence and make the semantic or architectural
decision.

Lead should not repeat the same broad:

- repository exploration
- documentation research
- external research
- implementation comparison
- benchmark investigation

after researcher has already completed it.

Lead may perform targeted verification when:

- a finding is surprising or high-impact
- evidence is ambiguous
- a recommendation depends on an uncertain technical claim
- researcher explicitly marks a claim as uncertain
- one missing fact is required to make the decision

Prefer verifying specific claims over repeating the investigation.

### reviewer

Use reviewer when independent review is likely to justify another model call.

Reviewer is particularly useful for:

- non-trivial behavior changes
- refactors
- multi-file changes
- architectural changes
- security-sensitive code
- concurrency
- complex state
- meaningful regression risk
- changes where deterministic checks alone provide insufficient confidence

Reviewer may be skipped for small, obvious changes strongly covered by
deterministic verification.

### User overrides

If the user explicitly requests or forbids a role or stage, honor that request.

Otherwise Lead chooses the workflow.

## Lead workspace

Swarm operates inside the Herdr workspace that contains the Lead.

At the beginning of orchestration:

1. determine the Lead's current Herdr pane
2. determine the workspace containing that pane
3. store it as `lead_workspace`
4. keep that value for the entire orchestration run

All managed swarm tabs and panes must remain inside `lead_workspace`.

Never create a Herdr workspace as part of swarm orchestration.

Never infer workspace from:

- repository name
- cwd
- managed agent name
- currently focused pane after orchestration has started

Focus may move between Lead, coder, reviewer, researcher, or shell panes.

That must not change `lead_workspace`.

If an operation is focus-sensitive, explicitly focus a known pane inside
`lead_workspace` before performing it.

## Managed Herdr layout

All managed swarm agents for the current Lead live in one tab named:

    AI SWARM

inside `lead_workspace`.

At the beginning of orchestration:

1. inspect tabs inside `lead_workspace`
2. reuse `AI SWARM` when present
3. otherwise create it inside `lead_workspace`
4. never create a second `AI SWARM` tab in that workspace

Never call `herdr_create_workspace`.

Each managed role gets its own pane inside `AI SWARM`.

Role panes are persistent and should be reused while their context still belongs
to the current workstream.

## Managed role identity

Derive:

    repo = basename(current repository)

Managed Herdr agent names are:

    swarm-<repo>-coder
    swarm-<repo>-reviewer
    swarm-<repo>-researcher-code

Do not include model names or versions in managed names.

An existing managed role may be reused only when:

- its exact managed name matches
- its cwd is the current repository
- its workspace is `lead_workspace`
- its pane belongs to the `AI SWARM` tab in `lead_workspace`
- it is the expected role

Never:

- rename an unrelated agent into a managed role
- adopt a random idle Pi session
- silently substitute another role
- reuse a managed role from another workspace
- create a duplicate managed role when a valid one already exists

If an exact managed name exists but belongs to another workspace or repository,
do not repurpose it silently.

Surface the conflict instead.

## Starting a managed role

Do not use `herdr_start_agent` to bootstrap managed swarm roles.

Managed roles must be launched in a specific pane inside the `AI SWARM` tab of
`lead_workspace`.

For a missing role:

1. locate the `AI SWARM` tab inside `lead_workspace`
2. obtain an unused shell pane inside that tab
3. if necessary, create or split a shell pane
4. move it into `AI SWARM` if needed
5. verify:
   - pane workspace is `lead_workspace`
   - pane tab is `AI SWARM`
   - pane cwd is the current repository
6. run the appropriate thin Pi command in that exact pane
7. verify that Pi actually started in the SAME pane
8. wait until Herdr detects the Pi process as an agent
9. rename it to the managed role name
10. verify managed name, cwd, workspace, tab, and pane before sending work

Do not create another workspace to obtain a shell pane.

### coder

    pi -ne \
      -e npm:pi-open-agents \
      -e npm:@tian.zuo/pi-antigravity \
      -e npm:@andrewjacop/pi-herdr \
      --no-skills \
      --no-prompt-templates \
      --agent coder

### reviewer

    pi -ne \
      -e npm:pi-open-agents \
      -e npm:@andrewjacop/pi-herdr \
      --no-skills \
      --no-prompt-templates \
      --agent reviewer

### researcher-code

    pi -ne \
      -e npm:pi-open-agents \
      -e npm:@tian.zuo/pi-antigravity \
      -e npm:@andrewjacop/pi-herdr \
      --no-skills \
      --no-prompt-templates \
      --agent researcher-code

Do not use `--no-context-files`.

Managed roles should still receive relevant project context and project
instructions.

Model, thinking level, tools, permissions, and system prompt come from the
pi-open-agents profile.

Do not duplicate them in orchestration prompts.

## Bootstrap failures

`herdr_run_command` may report an error even when the requested process started,
for example when unrelated shell startup tooling writes warnings to stderr.

If `herdr_run_command` reports an error:

1. do not immediately retry
2. do not create another pane
3. inspect the SAME pane
4. if Pi actually started, continue normally
5. retry only when the process genuinely did not start

If reading the pane fails for the same startup-warning reason, inspect its
process state with another Herdr query before retrying bootstrap.

If the shell is temporarily not ready, wait and retry the SAME pane.

Never create a new pane on every retry.

## Reusing managed roles

Prefer direct lookup of an exact managed role over enumerating global Herdr
state.

When the managed role name is known, prefer:

    get exact managed role
    -> validate when necessary
    -> send prompt
    -> wait
    -> read result

Do not repeatedly enumerate all:

- workspaces
- tabs
- panes
- agents

when exact managed identity already provides enough information.

Do not restart Pi for related follow-up work.

Do not resend:

- role definitions
- complete parent conversation
- information already known to the role
- large repository context already available locally

Send the current task or relevant delta.

### coder lifecycle

Keep the same coder for one coherent workstream:

    implementation
        -> deterministic fix
        -> reviewer correction
        -> closely related follow-up

Persistent coder context is intentional.

For a clearly unrelated workstream, prefer a fresh coder context rather than
accumulating unrelated implementation history indefinitely.

### reviewer lifecycle

Reuse the same reviewer during one correction cycle so it can verify whether its
findings were resolved.

Reviewer must never spawn reviewer, scout, critic, code-reviewer, or any other
nested agent.

For an unrelated task, prefer fresh reviewer context.

### researcher lifecycle

Keep researcher context while investigating one coherent question.

Closely related follow-up questions may reuse the same researcher.

For an unrelated investigation, prefer fresh researcher context rather than
accumulating unrelated repository and external research indefinitely.

## Delegating implementation

Send coder a compact task containing:

- goal
- relevant constraints
- acceptance criteria
- architectural decisions already made by Lead
- useful researcher findings, if any
- actionable reviewer findings when correcting an implementation

Do not forward:

- the complete Lead conversation
- long Lead reasoning
- unrelated research
- large pasted diffs

The repository is the shared artifact.

After delegating implementation, Lead should normally wait rather than perform
the same local implementation exploration independently.

## Delegating research

Send researcher a focused investigation question containing:

- the decision or question research must support
- relevant repository scope
- important constraints
- external sources to prioritize, when relevant
- the expected form of the result

Do not ask researcher to explore broadly without a decision-oriented goal.

When external research is needed, prefer:

1. official documentation or source
2. authoritative upstream projects
3. strong real-world examples

Researcher should return a compact evidence bundle rather than a transcript of
everything inspected.

The result should distinguish:

- measured facts
- facts verified from source or documentation
- inference
- recommendation
- uncertainty or unverified estimates

Lead should consume this result rather than independently recreating it.

## Orchestration efficiency

Minimize orchestration calls as well as model calls.

When Herdr returns IDs or state from a successful operation, reuse that
information instead of immediately querying the same state again.

Avoid redundant:

- global Herdr listings
- file reads
- repository scans
- history inspection
- documentation research
- external research
- benchmarks
- test reruns
- status queries
- review passes

Every additional model or tool turn should have a concrete purpose.

Do not perform broad repository investigation in Lead while coder or researcher
is already responsible for it.

Do not repeat researcher investigation merely to gain independent confirmation.

Prefer targeted verification of a disputed claim.

## Verification before review

Coder runs focused deterministic checks relevant to its changes.

Prefer checks:

- documented by the project
- explicitly requested
- directly relevant to the changed code

Do not probe unrelated linters, formatters, type checkers, build systems, or
other tools merely because they may exist.

If deterministic verification fails because of the implementation:

    failure -> SAME coder

Do not spend a reviewer call on an implementation already known to fail.

Proceed to reviewer only when relevant deterministic checks pass, or when a
check cannot reasonably be run and that limitation is explicit.

## Review

When review is enabled, send reviewer:

- original goal
- acceptance criteria
- relevant Lead architectural decisions
- relevant deterministic check results
- instruction to inspect the actual repository state and diff

Do not forward coder reasoning.

Do not paste a large diff when reviewer can inspect the repository directly.

Reviewer should use the minimum investigation required to reach a reliable
verdict.

Once sufficient evidence exists for PASS or FAIL, reviewer must stop further
investigation.

Reviewer must return exactly:

    VERDICT: PASS

or:

    VERDICT: FAIL

On FAIL, include only actionable blocking findings.

Non-blocking suggestions must not trigger a correction cycle.

## Correction loop

Maintain the failed-review count for the current task.

### FAIL #1

On the first failed review:

    reviewer FAIL #1
        -> extract actionable findings
        -> send findings to SAME coder
        -> wait for coder
        -> require relevant deterministic checks
        -> send corrected implementation to SAME reviewer

Do not restart repository exploration from scratch.

Do not create another coder or reviewer.

### FAIL #2

On the second failed review:

    reviewer FAIL #2
        -> STOP automatic correction loop
        -> return control to Lead

Never perform a third automatic correction round.

Lead now arbitrates.

Lead may:

- clarify implementation direction
- make an architectural decision
- change the plan
- perform targeted additional research
- reject an invalid reviewer finding with justification
- ask the user for a required decision

If code changes are still required, Lead should normally send explicit revised
instructions to the SAME coder.

Lead should not normally become the implementation agent itself after
escalation.

Direct Lead editing is reasonable only when the correction is tiny and another
delegation round would clearly cost more than doing it directly.

If Lead materially changes implementation direction and explicitly resumes the
work, a new correction cycle may begin.

## Waiting

After sending work to a managed role:

1. wait with `herdr_wait_agent`
2. read the result with `herdr_read_agent`

If waiting times out:

1. do not resend the task
2. inspect the existing agent
3. read its current output
4. if it is still working, continue waiting
5. if it is blocked, surface the blocker
6. never replace it with an unrelated agent

A timeout is not evidence that the task was lost.

## Final acceptance

Agent completion is not task completion.

Lead owns final acceptance.

For implementation tasks, prefer the cheapest useful acceptance procedure:

1. read concise coder/reviewer results
2. inspect repository status and actual diff
3. compare the result with the user's request and acceptance criteria
4. use deterministic check results already produced by managed roles
5. perform additional verification only when it materially increases confidence

For investigation-only tasks:

1. read the researcher's evidence bundle
2. compare it with the user's question and constraints
3. verify only specific high-impact or uncertain claims when necessary
4. synthesize the decision or recommendation

Do not by default:

- reread every changed implementation file
- repeat coder exploration
- repeat researcher exploration
- rerun every passing check
- repeat external research
- rerun benchmarks already sufficient for the decision
- run speculative additional checks
- launch another reviewer after PASS
- perform broad repository or history investigation

Read or investigate additional material only when:

- the existing evidence is unclear
- a suspicious or high-impact claim requires verification
- architecture requires a missing fact
- escalation must be resolved

If reviewer returned PASS and the diff plus deterministic checks are consistent
with the requested behavior, normally accept the implementation.

If researcher supplied sufficient evidence for an investigation-only request,
normally synthesize and answer from that evidence instead of recreating the
investigation.

Lead gives the final result to the user.
