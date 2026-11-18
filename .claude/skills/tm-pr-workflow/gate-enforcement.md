# How the gate is enforced, and the shapes of the push and PR commands

Moved word for word from `SKILL.md`, "Tier 1: the local gate" (the part that starts at "How it is enforced"). The rules are unchanged; `SKILL.md` keeps their headline.

How it is enforced, and what that means for the order of operations:

- A Claude Code `PreToolUse` hook (`.claude/settings.json` →
  `scripts/claude-hooks/block-git-push.sh`) blocks any Bash call containing `git push`
  or `gh pr create` unless `.git/.pre-push-check-passed` is **newer than the last commit**. So the order is
  always **commit → run the gate → push**. Any new commit (a fix, an amend, a review
  change) needs a fresh gate run before the next push.
- The gate decides whether to run the iOS steps from **committed** changes only
  (`git diff --no-renames <merge-base with origin/main> HEAD`). Uncommitted iOS edits won't trigger
  them, which is one more reason to commit first.
- The hook matches on command text. Any Bash call that merely *mentions* `git push` or `gh pr create` (a
  commit message or PR body passed inline) is blocked until the gate has passed. Pass long
  text through a file: `git commit -F <file>`, `gh pr create --title "<PR title>" --body-file <file>`.
- **The deny rules match the whole command text too.** `.claude/settings.json` denies a Bash command whose
  text matches a pattern such as `*local.properties*`, `*.env*` or `*Secrets.xcconfig*`, and the text is
  everything in the command: a heredoc body, an `echo`, an inline commit message or PR body, not only a path
  argument. A note or draft that merely names one of those files is denied the same way (the Maps key is read
  from `local.properties`, so a board record or a PR text names it). Write such text with the Write or Edit tool
  and give a command its path (`git commit -F <file>`, `--body-file <file>`, `queue.sh add --task <file>`). The
  rules are the guard against reading those files: never weaken them, never route a denied command around them
  (`tm-agent-loop`, "When the permission classifier denies a command", `denied-commands.md`).
- **Shapes of the push and PR commands.** The hooks read the command text and the session
  directory, so use these shapes and nothing cleverer:
  - Run the gate as a command of its own, from the clone: `scripts/pre-push-check.sh`.
  - Push with `git push -u origin <branch>` (or `HEAD`), alone or followed by a suffix such as
    `2>&1 | tail -5`. Open the PR with `gh pr create --base main --title "<PR title>" --body-file <file>`
    (`gh` refuses without `--title` when it is not interactive; `<file>` is the draft without its
    `Title:` line, see "PR description", `commits-push-pr.md`), the same suffix allowed. The branch must exist locally.
  - From another directory: `git -C <absolute path of the clone> push -u origin <branch>`, or
    `cd <absolute path of the clone> && git push -u origin <branch>`. A `cd` target with `~`, a
    variable, `-` or a missing directory, or a `cd` inside `( )`, `{ }` or a `||` list, blocks the
    push (the hook cannot read it).
  - Not in a wrapper (`env`, `bash -c`, `xargs`, `echo`), not with `--all`, `--mirror` or `--tags`.
  - Creating a branch: run `scripts/prune-merged-branches.sh` as a command of its own first. The
    branch-create hook checks before the whole command runs, so `scripts/prune-merged-branches.sh &&
    git switch -c <branch>` in one command is blocked; the next command is `git switch -c <branch>`.
  Each hook's block message names the command to run instead.
- `./gradlew test` on its own runs zero tests. KMP tests only run under `allTests`. Use
  the gate script, not a hand-picked Gradle command, and read test counts from `allTests`.
