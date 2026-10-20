# Regression checks

Use `scripts/test-discover.sh` for deterministic discovery tests. The model checks in `evals.json` test interpretation and task completion separately; passing discovery is not passing an audit.

## Inputs

`files/fixture.json` contains a self-contained, intentionally unversioned source tree and two override sets. The toy engine specification is input evidence, not a claim about real applications.

Materialize a fresh external tree before each model run. For example, from this evaluation directory:

```sh
out=$(mktemp -d "${TMPDIR:-/tmp}/kaizen-audit-input.XXXXXX")
python3 - files/fixture.json "$out" correct <<'PY'
import json
from pathlib import Path
import sys
manifest = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2]).resolve()
files = manifest['files'] | manifest['overrides'].get(sys.argv[3], {})
for name, content in files.items():
    path = Path(name)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError(name)
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content)
print(root)
PY
```

Use `correct` for case 1, `mutated` for case 2, and repeat case 1 with `heldout`. The held-out variant changes layout comments and an extra helper alias while preserving the required actions. Case 3 uses a frozen real repository tree, not the toy fixture.

## Comparison

Snapshot the old skill before editing. Use identical prompts, inputs, model/provider, thinking level, tool access and environment for old/new runs. For the current Luna controls, pin `openai-codex/gpt-6-luna`, disable extensions/MCP/other skills and delegation, and explicitly load only the skill under test. This isolates skill behavior; it does not test the user's full extension stack.

Capture the JSON event stream, stderr, actual exit, timing and model IDs. Keep any watchdog external and distinguish its activation from a normal model stop. Check input hashes and tool results, not just the final report or ledger labels. Read-only tools plus a shell are not a security sandbox.

Grade completion, supported findings, false positives and preservation separately. In particular, check action applicability and Russian helper dispatch in addition to the headline expected defects. Requirements may be satisfied by extra aliases; unrelated OS and application workspace actions are not interchangeable. Record newly discovered assertion gaps as post-hoc checks rather than silently improving the original score.

Small controlled inputs can validate a reasoning branch without demonstrating whole-repository reliability. Single, unblinded runs are exploratory evidence, not a statistically reliable benchmark. The rewrite's initial Luna comparisons still failed full-repository completion; treat the workflow as experimental rather than a proven solution.
