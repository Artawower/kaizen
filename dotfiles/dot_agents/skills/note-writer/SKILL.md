---
name: note-writer
description: Review English text edits in org-mode files from a git diff. Checks grammar, style, translation quality (RU→EN), and produces a clean patch. Use when reviewing org-mode writing, checking English quality of documentation edits, or auditing translation naturalness.
---

# EN Writing & Translation QA (org-mode, git diff)

VERSION: 1.1

## Goal

Review English text edits provided as a unified git diff (source text is org-mode) and help the user:

- fix grammar errors
- improve style and clarity
- assess translation quality (RU→EN influence)
- explain each issue with a short rule-based note
- propose better rewrites while preserving meaning and org-mode markup

## Input

- git_diff (required): unified diff of an org-mode file — provide inline or ask the user to paste it
- optional context: audience, tone, register; English variant (American/British); strictness (low/medium/high)

## Scope

- Review ONLY added/modified lines from the diff.
- Use removed lines only for context.
- Do not rewrite the whole document.
- If a change creates a consistency problem with unchanged nearby text, mention briefly.

## Process

1. **Parse the diff** — identify hunks, classify lines (`+` added, `-` removed, ` ` context). Pair removed/added blocks when it is clearly a modification.

2. **Grammar & correctness pass** — for each changed line detect mistakes (articles, prepositions, tense, agreement, punctuation, sentence boundaries, word order). Provide: Problem → Fix → Explanation.

3. **Style & clarity pass** — improve naturalness and flow with minimal edits. Prefer concise, idiomatic English. Preserve tone/voice unless it harms clarity.

4. **Translation quality check** — detect Russianisms and literal translation patterns: unnatural collocations, incorrect prepositions/articles, calques/false friends, overly heavy nominalizations, passive voice where unnatural, word order mirroring Russian. Give 1–2 plausible meanings when ambiguous, offer safe rewrites.

5. **Rule snippet for every flagged issue** — Rule name + 1–2 sentence explanation + tiny example if helpful.

6. **Produce final rewrite** — "Suggested patch (clean)" section with revised lines only, no diff markers, org-mode markup preserved.

## Priority levels

- **High**: grammar error, meaning distortion, clearly non-native/incorrect collocation, broken org syntax
- **Medium**: awkward but understandable, wordiness, minor punctuation
- **Low**: optional polish, alternative phrasing

## Output format

1. Overall assessment — Grammar / Style/flow / Translation naturalness
2. Issues list (prioritized High → Medium → Low), each with: Problem → Fix, Why, Rule snippet
3. Suggested patch (clean) — revised lines, no diff symbols, org-mode markup intact
4. Optional: 3 learning takeaways (recurring patterns)

## Constraints

- Respond in the user's language for meta-commentary; keep proposed English rewrites in English.
- Ask max 2 clarification questions, only if meaning is genuinely unclear.
- Do not introduce new facts or content.
- Do not remove org-mode markup unless broken; explain any markup changes.
