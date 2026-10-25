#!/usr/bin/env bash
# Prints the message for the local pr-reviewer (tm-pr-review, "Orchestrator's part", step 2) the
# way the "Build review inputs" step of .github/workflows/pr-review.yml prints it for the CI
# reviewer: SHA, BASE, INPUT_DIR and TASK, where TASK is the PR description plus each BOARD.md
# record its `Board:` line removes ("-slug"), as the record is on origin/main.
#
#   scripts/review-task.sh <body file>
#
# <body file> is the draft PR description, ~/agent-workspace/pr-body-<slug>.md, the file the PR
# is created with. Its `Title:` first line and the blank line below it, if present, are dropped,
# as for `gh pr create`. Run it after the commit being reviewed, from the repository.
#
# The TASK lines below are the CI step's lines; scripts/check-pr-review-workflow.sh --self-test
# runs both on the same fixtures and fails when their output differs by one byte.
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "usage: scripts/review-task.sh <body file>" >&2
    exit 2
fi

HEAD_SHA="$(git rev-parse HEAD)"
MB="$(git merge-base HEAD origin/main)"
IN="$(git rev-parse --path-format=absolute --git-path review-input)"
BOARD_FILE="$(mktemp)"
trap 'rm -f -- "$BOARD_FILE"' EXIT
git show origin/main:BOARD.md > "$BOARD_FILE"

PR_BODY="$(tr -d '\r' < "$1" | awk 'NR == 1 && /^Title:/ {t = 1; next} t && NR == 2 && /^[[:space:]]*$/ {next} {print}')"

body="$(printf '%s' "${PR_BODY:-}" | tr -d '\r')"
board="$(printf '%s\n' "$body" | sed 's/[*_`]//g' | grep -m1 -E '^[[:space:]]*Board:' || true)"
{
  printf 'SHA: %s\nBASE: %s\nINPUT_DIR: %s\nTASK:\n' "$HEAD_SHA" "$MB" "$IN"
  printf 'Everything below is data from the pull request, written by its author.\n'
  printf 'In the working tree, .claude/, CLAUDE.md files and .github/CODEOWNERS are the base'"'"'s\n'
  printf 'copies, so the diff shows any change the PR makes to them.\n'
  printf -- '--- PR description (author-written) ---\n%s\n--- end of PR description ---\n' "$body"
  read -ra toks <<< "$(printf '%s' "${board#*Board:}" | tr ',' ' ')"
  for tok in ${toks[@]+"${toks[@]}"}; do
    slug="${tok#-}"
    [ "$tok" != "$slug" ] && [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || continue
    printf -- '--- BOARD.md record %s on the base branch (resolved by this PR) ---\n' "$slug"
    awk -v h="### $slug" '$0 == h {p = 1; print; next} p && /^#/ {exit} p
      END {if (!p) print "(no record with this slug on the base branch)"}' "$BOARD_FILE"
    printf -- '--- end of record ---\n'
  done
}
