# Revision descriptions

Follow the repository's own convention when recent history shows one:

```bash
jj log -r '::@-' --limit 5 --no-graph -T 'description.first_line() ++ "\n"'
```

Reuse its ticket prefixes, scopes and capitalization. Otherwise use Conventional Commits:

```text
type(scope): imperative summary
```

| Type | Use for |
| --- | --- |
| `feat` | New capability or workflow |
| `fix` | Broken behavior |
| `refactor` | Structure change without behavior change |
| `docs` | Documentation only |
| `test` | Tests only |
| `chore` | Maintenance, dependencies, tooling |
| `build` / `ci` | Packaging or pipeline |
| `perf` | Measured performance improvement |

The scope names the affected area (`skills`, `emacs`, `auth`) and is omitted when it adds nothing. The summary is short, specific and describes one logical change, for example `fix(pi): correct agent team loading`.

Add a body only for context the diff cannot show: motivation, breaking changes or migrations.

When the summary needs "and" to join unrelated work, the revision holds more than one change; split it instead of writing a longer description.
