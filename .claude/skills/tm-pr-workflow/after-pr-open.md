# After the PR is open: the human's part

Read from `SKILL.md`, "After the PR is open". The rules are there; this file holds the human's steps, for context.

1. CI runs on the PR. It should already be green because the gate mirrors it.
2. The human checks the Tier 2 list (CI's `pr-reviewer` checks it too, `tm-pr-review`
   item 11): a test named for each user-visible behavior, or a valid reason for a human
   check, and does any human check it lists.
3. The human reviews the structure: does it follow the established pattern, respect module
   boundaries, and avoid duplicating something that should be shared?
4. Only then does the human merge into `main`, unless the PR meets the merge conditions in
   `tm-agent-loop`: then the agent merges it, and the human does step 2's human checks
   when testing the feature (the epic-level Tier 2). `tm-agent-loop` also has the
   after-merge cleanup and how to read the CI reviewer's verdict.
