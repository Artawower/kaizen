# Splitting a revision

`jj split` stays non-interactive when it receives `-m` and a fileset. The selected files form the first revision, which keeps the original change ID and takes the new message. The remaining changes move to a new child revision that keeps the original description.

When splitting `@`, the remaining part stays as the working copy `@`. When splitting another revision, find the remaining part with `jj log -r 'children(<rev>)'`.

## Steps

1. Inspect the revision: `jj diff --stat -r <rev>`, then `jj diff -r <rev>`.
2. Group the files by logical concern: feature versus fix, implementation versus config, one module per group.
3. Split off the first group:

   ```bash
   jj split -r <rev> -m "<first description>" <paths>
   ```

4. Repeat on the remaining part for each further group. The last group needs no split; describe it with `jj describe -r <remaining> -m "<description>"`.
5. Confirm with `jj log` that each revision holds one change and has a description.

## Placement

| Goal | Flag |
| --- | --- |
| Put the selected files on another base | `-o <destination>` |
| Insert the selected files before or after a revision | `-B <rev>` / `-A <rev>` |
| Make both parts siblings instead of parent and child | `-p` |

## Filesets

Quote patterns so the shell does not expand them: `"src/auth/**"`, `"all() ~ 'tests/**'"`.

A file holding hunks for several concerns cannot be separated by fileset. Insert an empty revision below it with `jj new -B <rev> -m "<first description>"`, edit the file there to contain only the first concern's hunks, then return with `jj edit <rev>`. The descendant rebases cleanly and keeps only the remaining hunks.
