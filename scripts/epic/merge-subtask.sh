#!/usr/bin/env bash
# The local merge of a subtask into the integration branch of an epic (epic-orchestration, subtask-merge.md,
# step 7), and the only way a subtask gets there: it refuses unless everything the earlier steps promise is true.
#
#   scripts/epic/merge-subtask.sh <id> <subtask branch> --title "<type(scope): summary>" --attribution "<trailer line>" [--gated-at <sha>]
#   scripts/epic/merge-subtask.sh --self-test
#
# Run it from the main clone with the integration branch (`feature/epic/<slug>`) checked out and clean. It merges
# <subtask branch> with `git merge --no-ff`, one commit with the trailers `Epic-Subtask: <id>` and the attribution line.
# It refuses (exit 1, the reason on stderr, nothing changed) when:
#   - the checked-out branch is not `feature/epic/*`, or the tree is not clean;
#   - the subtask branch does not exist, or its id is already merged (an `Epic-Subtask: <id>` trailer on the branch);
#   - the integration tip is not in the subtask branch (bring it up first: subtask-merge.md, step 2), so the commit that
#     was gated is the tree that lands;
#   - there is no gate pass for exactly that commit: scripts/pre-push-check.sh appends the commit it gated to
#     `.gate-passed-heads` in the git dir when its run passed, and this script reads that file, never a log, a wrapper's
#     exit code or the agent's memory (scripts/gate-result.sh reads a log for the same reason). `--gated-at <sha>` names a
#     later commit that holds the subtask branch's head and has the pass: for subtasks the plan gates together (the
#     gate ran once on the combination); the sha must contain the subtask's head;
#   - scripts/local-review-gate.sh does not allow the subtask branch's head (no recorded review, a blocking finding, an
#     undisposed important finding).
#
# Exit: 0 merged, 1 refused, 2 usage error. Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
REVIEW_GATE="${TM_REVIEW_GATE:-$SCRIPT_DIR/../local-review-gate.sh}"
USAGE='usage: scripts/epic/merge-subtask.sh <id> <subtask branch> --title "<type(scope): summary>" --attribution "<trailer line>" [--gated-at <sha>] | --self-test'

refuse() { echo "merge-subtask: refused: $*" >&2; exit 1; }

merge() {
    local id="$1" branch="$2" title="" attribution="" gated="" current head tip passed out
    shift 2
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --title) [ "$#" -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; title="$2"; shift 2 ;;
            --attribution) [ "$#" -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; attribution="$2"; shift 2 ;;
            --gated-at) [ "$#" -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; gated="$2"; shift 2 ;;
            *) echo "$USAGE" >&2; exit 2 ;;
        esac
    done
    [ -n "$title" ] && [ -n "$attribution" ] || { echo "$USAGE" >&2; exit 2; }
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "$USAGE" >&2; exit 2; }

    current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || refuse "not inside a git work tree"
    case "$current" in feature/epic/*) ;; *) refuse "the checked-out branch is '$current', not the integration branch feature/epic/<slug>" ;; esac
    [ -z "$(git status --porcelain)" ] || refuse "the working tree is not clean"
    head="$(git rev-parse --verify --quiet "refs/heads/$branch^{commit}")" || refuse "the subtask branch '$branch' does not exist"
    tip="$(git rev-parse HEAD)"
    if git log "$current" --format='%B' | grep -qxF "Epic-Subtask: $id"; then
        refuse "subtask $id is already merged into $current (an Epic-Subtask: $id trailer is on the branch)"
    fi
    git merge-base --is-ancestor "$tip" "$head" \
        || refuse "the tip of $current (${tip:0:12}) is not in $branch: bring it up first (subtask-merge.md, step 2), so the gated tree is the one that lands"

    if [ -n "$gated" ]; then
        gated="$(git rev-parse --verify --quiet "$gated^{commit}")" || refuse "--gated-at names no commit"
        git merge-base --is-ancestor "$head" "$gated" || refuse "--gated-at ${gated:0:12} does not contain the head of $branch (${head:0:12})"
    else
        gated="$head"
    fi
    passed="$(git rev-parse --path-format=absolute --git-path .gate-passed-heads)"
    if [ ! -f "$passed" ] || ! grep -qxF "$gated" "$passed"; then
        refuse "no green gate is recorded for exactly ${gated:0:12}: run scripts/pre-push-check.sh on it and read its own GATE_EXIT line (scripts/gate-result.sh); a wrapper's exit code is not a result"
    fi
    out="$("$REVIEW_GATE" check "$head" 2>&1)" || refuse "no allowed local review for the head of $branch (${head:0:12}): $out"

    git merge --no-ff "$branch" -m "$title (subtask $id)" -m "Epic-Subtask: $id" -m "$attribution" >/dev/null \
        || { git merge --abort 2>/dev/null; refuse "git merge failed (conflicts are a plan defect: two subtasks' allowed_paths overlapped)"; }
    echo "merged $branch as $(git rev-parse --short HEAD) (subtask $id), gate pass for ${gated:0:12}"
}

self_test() {
    local tmp fails=0 repo out rc gated
    tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    check() { # check <description> <expected substring> <expected exit> <command...>
        local d="$1" want="$2" wantrc="$3"; shift 3
        out="$("$@" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$wantrc" ] && printf '%s' "$out" | grep -qF -- "$want"; then echo "ok   $d"
        else echo "FAIL $d: expected exit $wantrc and '$want', got exit $rc:" >&2; printf '%s\n' "$out" | sed 's/^/       /' >&2; fails=$((fails + 1)); fi
    }
    repo="$tmp/repo"; git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
    echo base > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -q -m base
    git -C "$repo" switch -q -c feature/epic/demo
    git -C "$repo" switch -q -c chore/demo-s1; echo one > "$repo/s1.txt"; git -C "$repo" add -A; git -C "$repo" commit -q -m "s1"
    git -C "$repo" switch -q -c chore/demo-s2 feature/epic/demo; echo two > "$repo/s2.txt"; git -C "$repo" add -A; git -C "$repo" commit -q -m "s2"
    git -C "$repo" switch -q feature/epic/demo
    printf '#!/bin/sh\necho "allowed: $2 APPROVE"\n' > "$tmp/review-ok"; printf '#!/bin/sh\necho "blocked: no report"\nexit 1\n' > "$tmp/review-no"
    chmod +x "$tmp/review-ok" "$tmp/review-no"
    run() { (cd "$repo" && TM_REVIEW_GATE="$tmp/review-ok" bash "$SELF" "$@"); }
    local s1 s2 pass
    s1="$(git -C "$repo" rev-parse chore/demo-s1)"; s2="$(git -C "$repo" rev-parse chore/demo-s2)"
    pass="$repo/.git/.gate-passed-heads"
    check "usage error exits 2" "usage:" 2 bash "$SELF"
    check "no gate pass recorded is refused" "no green gate is recorded for exactly ${s1:0:12}" 1 run S1 chore/demo-s1 --title "chore(x): s1" --attribution "Co-Authored-By: T <t@x>"
    echo "$s2" > "$pass"
    check "a pass for another commit is refused" "no green gate is recorded for exactly ${s1:0:12}" 1 run S1 chore/demo-s1 --title "chore(x): s1" --attribution "Co-Authored-By: T <t@x>"
    echo "$s1" >> "$pass"
    check "a review that is not allowed is refused" "no allowed local review" 1 bash -c "cd '$repo' && TM_REVIEW_GATE='$tmp/review-no' bash '$SELF' S1 chore/demo-s1 --title 't' --attribution 'a'"
    check "a missing branch is refused" "does not exist" 1 run S9 chore/none --title "t" --attribution "a"
    check "a gated subtask merges" "merged chore/demo-s1" 0 run S1 chore/demo-s1 --title "chore(x): s1" --attribution "Co-Authored-By: T <t@x>"
    check "the merge commit has the trailer" "Epic-Subtask: S1" 0 git -C "$repo" log -1 --format=%B
    check "a merged subtask is refused a second time" "already merged" 1 run S1 chore/demo-s1 --title "t" --attribution "a"
    check "the integration tip must be in the subtask branch" "is not in chore/demo-s2" 1 run S2 chore/demo-s2 --title "t" --attribution "a"
    git -C "$repo" switch -q chore/demo-s2; git -C "$repo" merge -q --no-edit feature/epic/demo; git -C "$repo" switch -q feature/epic/demo
    s2="$(git -C "$repo" rev-parse chore/demo-s2)"
    check "a brought-up head has no pass yet" "no green gate is recorded for exactly ${s2:0:12}" 1 run S2 chore/demo-s2 --title "t" --attribution "a"
    check "--gated-at must contain the head" "does not contain the head" 1 run S2 chore/demo-s2 --title "t" --attribution "a" --gated-at main
    git -C "$repo" switch -q chore/demo-s2; echo three > "$repo/s3.txt"; git -C "$repo" add -A; git -C "$repo" commit -q -m "s3"; git -C "$repo" switch -q feature/epic/demo
    gated="$(git -C "$repo" rev-parse chore/demo-s2)"; echo "$gated" >> "$pass"
    check "a unit merges on the pass of the combination" "merged chore/demo-s2" 0 run S2 chore/demo-s2 --title "chore(x): s2" --attribution "a" --gated-at "$gated"
    echo dirty > "$repo/x.txt"
    check "a dirty tree is refused" "working tree is not clean" 1 run S3 chore/demo-s2 --title "t" --attribution "a"
    rm "$repo/x.txt"; git -C "$repo" switch -q main
    check "a branch that is not the integration branch is refused" "not the integration branch" 1 run S3 chore/demo-s2 --title "t" --attribution "a"
    if [ "$fails" = 0 ]; then echo "merge-subtask.sh self-test: all passed"; else echo "merge-subtask.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]; exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    "" | -*) echo "$USAGE" >&2; exit 2 ;;
    *) [ "$#" -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; merge "$@" ;;
esac
