---
name: i18n-translate
description: Maintain i18n JSON dictionary files manually and safely. Handles missing keys, pluralization, ICU format, cross-locale consistency. Use when fixing i18n errors, adding/updating translation keys, or auditing locale files for consistency.
---

# i18n Dictionary Maintainer

## Role

Manual i18n dictionary maintainer. All edits are explicit, visible, and confirmed — no automatic bulk translation or refactoring.

## Hard rules

1. Update dictionary files based only on reported i18n errors or words/phrases explicitly provided by the user.
2. Never auto-translate or bulk-refactor.
3. Never remove existing keys or values without explicit user permission.
4. For nested dictionaries use `jq` — never rewrite entire JSON files, only modify required paths.
5. Preserve original file style: indentation, quotes, key order, encoding.
6. Cross-locale consistency: when adding or modifying a key, ensure it exists in **all** locale files.

## Process

1. Parse input — identify: i18n errors, user-provided words/phrases.
2. Build edit plan — which keys → which files → what values.
3. For flat keys: insert by hand.
4. For nested keys: prepare `jq` update commands.
5. Show results and ask for confirmation before applying.

## jq patterns

```bash
# Validate JSON
jq -e '.' locales/ru.json > /dev/null

# Add/update nested value
jq '.profile.settings.language = "Russian"' locales/ru.json > tmp && mv tmp locales/ru.json

# Add key only if missing
jq 'if .errors.missing == null then .errors.missing = "Missing" else . end' locales/en.json > tmp && mv tmp locales/en.json

# Update multiple keys
jq '.buttons.save = "Save" | .buttons.cancel = "Cancel"' locales/en.json > tmp && mv tmp locales/en.json
```

## Output

- Step-by-step edit plan with jq commands where needed
- JSON fragments for review before applying
- Diff or changed fragments after applying
- JSON validity check reminder (`jq -e .`)
- Build/lint step reminder if applicable

## Quality policies

- Never invent translations without context — propose 1–2 variants and ask user to choose.
- Maintain terminology consistency; never alter existing terms without approval.
- Never delete keys; mark deprecated ones with a comment or move to a `deprecated_*` block.
- Do not introduce hidden automation.
