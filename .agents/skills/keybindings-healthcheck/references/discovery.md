# Discovery artifacts

`discover.sh` provides lexical leads, not an application registry, ownership verdict or exhaustive binding detector. It needs `sh`, `rg`, `find` and standard text utilities. Run it against the repository root; output must be a new external directory. An optional second argument selects an existing empty output directory, resolved relative to the caller's working directory. A zero exit and `READY` indicate successful enumeration and partitioning, not audit completion.

Start with `summary.txt` and `candidates.txt`. Use `matches.txt` only to locate a reason for selection; its previews are bounded to eight matches per file and 240 columns. Read the actual sources for interpretation. Filename matches can select empty files with no content hits.

At coverage reconciliation use:

| Artifact | Meaning |
| --- | --- |
| `inventory.txt` | Regular paths plus filesystem symlink paths in the structural scope. |
| `candidates.txt` | Text files selected by lexical filename or content patterns. |
| `remainder.txt` | Other text files, including potential loaders and dependencies. |
| `filtered.tsv` | Binary or filesystem-symlink classification, not an application exclusion. |
| `symlinks.txt` | Filesystem links requiring ownership/boundary decisions; targets were not opened. |
| `search-pattern.txt` | Content pattern used for this run. |

Candidates, remainder and filtered entries partition the inventory. Root `.arhive`, VCS metadata, skills, dependency directories and caches are structurally excluded. Regular files honor repository ignore files; parent/global ignores and ripgrep configuration are disabled for reproducibility. Documentation, tests and image extensions are not blanket exclusions: classify by actual execution/loading role. Passive prose and fixtures can be lexical false positives; executable literate files and utilities can be real bindings.

Filesystem symlinks are enumerated separately because ripgrep normally omits them. This structural scan includes ignored links. Inspect link metadata, then check ownership and resolved boundaries before following an in-tree dependency. Leave external or archived targets unopened, including links to directory trees. Native chezmoi `symlink_` source files are regular source data and can appear among text leads.

Keep referenced owned files even when they are in the remainder. When a component contains a candidate, inspect its entry point, selected profiles and automatic-loading directories rather than just the matching lines. Reconcile remainder paths by their roles; absence of a regex match is not evidence of no bindings. Record a generic exclusion reason for passive docs, tests or dependencies only after checking their role.

A nonzero exit or missing `READY` leaves incomplete artifacts. Inspect the exact error and recover before using counts. Newline, carriage-return and tab characters in filenames are rejected because the artifacts use line-based paths and TSV. Binary classification is heuristic, not a proof that a native file format contains no shortcuts; use the application's format when such a file is relevant.
