---
name: hate-resolver
description: Fix the most-counted unsolved annoyance from ~/tmp/hate.json, one per run.
disable-model-invocation: true
---

# Hate resolver

`~/tmp/hate.json` is the user's list of annoyances with their system. Each entry is a **hate**: `type` (the application), `hate` (the complaint), `count` (how often it bit), and `solved: true` once fixed. Resolve exactly one hate per run.

## 1. Pick

```bash
jq 'map(select(.solved != true)) | sort_by(-.count) | .[0]' ~/tmp/hate.json
```

This is the hate for this run; ties go to the earlier entry. Show it to the user in one line. Done when the user agrees to work on it; if they skip it, take the next entry of the same sorted list.

## 2. Investigate

Find where the `type` application is configured and how the complaint arises. Read the owning config and its project instructions, reproduce the behaviour when a command or headless run can show it, and form a hypothesis about the cause. Done when you can name the file and setting or code responsible, or know exactly what you cannot see without the user.

## 3. Ask

The complaint is a one-line note written in a moment of irritation. Ask the user what they were doing, what happened, and what they expected, plus anything step 2 left open. Ask a few questions at a time, and keep asking until you can state the expected behaviour in one sentence. Done when the user confirms that sentence.

## 4. Fix

Make the smallest change that delivers the confirmed behaviour, in its own revision, following the repository's rules. Verify it the way step 2 reproduced the problem. Done when the verification shows the expected behaviour, or you have told the user what only they can check.

## 5. Close

Ask the user whether the hate is gone. On a yes, set `"solved": true` on that entry alone and leave every other field and entry untouched. On a no, return to step 3 with what they observed.
