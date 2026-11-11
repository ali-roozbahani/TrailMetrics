#!/usr/bin/env bash
# The fallback for a queue PR that fell behind `main` outside the queue (the owner merged something
# else): asks GitHub to update the PR branch, then proves the update only moved the base, so the
# local review of the commit below it still holds (scripts/queue/local-verdict-for-head.sh). It never
# merges, rebases or pushes locally; it only fetches.
#
#   scripts/queue/update-branch.sh <PR number>          in the repository of the cwd
#   scripts/queue/update-branch.sh --self-test
#
# Steps:
#   1. GET repos/{owner}/{repo}/pulls/<N>: the PR must be open, its base `main`, its head a branch of
#      this repository (otherwise REFUSED).
#   2. GET repos/{owner}/{repo}/compare/main...<head sha>: `behind_by` 0 is UP_TO_DATE. (Not
#      `mergeable_state`, which GitHub computes lazily and which also says "behind" for other reasons.)
#   3. PUT repos/{owner}/{repo}/pulls/<N>/update-branch with expected_head_sha=<head sha>. GitHub
#      answers 202 and makes a signed merge commit of `main` into the branch (it does not run our
#      hooks). A refusal naming the expected head SHA is RACE, one naming a conflict is CONFLICT,
#      any other is REFUSED <GitHub's message>; expected when `main` changed a file under
#      .github/workflows/, which the token cannot write (no `workflow` scope).
#   4. GET the PR again until its head moves (every 5 s, at most 180 s). The new head's first parent
#      must be the old head (GET repos/{owner}/{repo}/commits/<new sha>), or it is RACE.
#   5. `git fetch origin main <head branch>`, then scripts/queue/merge-only-check.sh <new sha>.
#
# Output, one line:
#   UP_TO_DATE <head sha>             exit 0   nothing to do
#   UPDATED <new sha>                 exit 0   the update is merge-only
#   NOT_MERGE_ONLY <new sha> <reason> exit 1   the update is not merge-only: review it again
#   CONFLICT <message>                exit 1   update the branch by a local merge instead
#   REFUSED <reason>                  exit 1   not updated (see step 1 and 3, or the head did not move)
#   RACE <reason>                     exit 1   the head changed meanwhile: read the PR again
# Exit 2: usage error, a missing tool, a failed `gh` read or fetch, unreadable data.
# Environment, for the self-test: UPDATE_BRANCH_STEP (5), UPDATE_BRANCH_MAX_SECONDS (180).
# Bash 3.2 compatible.
set -u -o pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
DIR="$(dirname "$SELF")"
USAGE="usage: scripts/queue/update-branch.sh <PR number> | --self-test"

die() { echo "update-branch: $*" >&2; exit 2; }
out() { echo "$*"; exit "${CODE:-1}"; }

get() { # get <output file> <endpoint>
    gh api "$2" > "$1" 2>/dev/null || die "gh api failed reading $2"
}

update() {
    local n="$1" d state base ref head cross behind msg new p1 waited=0
    d="$(mktemp -d)"
    trap 'rm -rf -- "$d"' EXIT
    get "$d/pr.json" "repos/{owner}/{repo}/pulls/$n"
    state="$(jq -r '.state // empty' "$d/pr.json")" && base="$(jq -r '.base.ref // empty' "$d/pr.json")" \
        && ref="$(jq -r '.head.ref // empty' "$d/pr.json")" && head="$(jq -r '.head.sha // empty' "$d/pr.json")" \
        && cross="$(jq -r 'if .head.repo.full_name == .base.repo.full_name then "no" else "yes" end' "$d/pr.json")" \
        || die "PR $n is not readable"
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] || die "PR $n has no head sha"
    [ "$state" = open ] || out "REFUSED PR #$n is $state"
    [ "$base" = main ] || out "REFUSED the base of PR #$n is $base, not main"
    [ "$cross" = no ] || out "REFUSED the head of PR #$n is not a branch of this repository"

    get "$d/compare.json" "repos/{owner}/{repo}/compare/main...$head"
    behind="$(jq -er '.behind_by | numbers' "$d/compare.json" 2>/dev/null)" || die "compare data is not readable"
    [ "$behind" != 0 ] || CODE=0 out "UP_TO_DATE $head"

    if ! gh api -X PUT "repos/{owner}/{repo}/pulls/$n/update-branch" -f "expected_head_sha=$head" \
        > "$d/put.json" 2> "$d/put.err"; then
        msg="$(jq -r '.message // empty' "$d/put.json" 2>/dev/null)"
        [ -n "$msg" ] || msg="$(tr '\n' ' ' < "$d/put.err" | sed 's/ *$//')"
        case "$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')" in
            *"expected head sha"*) out "RACE $msg" ;;
            *conflict*) out "CONFLICT $msg" ;;
            *) out "REFUSED ${msg:-update-branch failed without a message}" ;;
        esac
    fi

    while :; do
        get "$d/pr.json" "repos/{owner}/{repo}/pulls/$n"
        new="$(jq -r '.head.sha // empty' "$d/pr.json")"
        [ "$new" = "$head" ] || break
        [ "$waited" -lt "$MAX" ] || out "REFUSED GitHub accepted the update but the head of PR #$n did not move within $MAX s"
        sleep "$STEP"
        waited=$((waited + STEP))
    done
    [[ "$new" =~ ^[0-9a-f]{40}$ ]] || die "PR $n has no head sha"
    get "$d/commit.json" "repos/{owner}/{repo}/commits/$new"
    p1="$(jq -r '.parents[0].sha // empty' "$d/commit.json")" || die "commit $new is not readable"
    [ "$p1" = "$head" ] || out "RACE the head of PR #$n moved to ${new:0:12}, which is not an update of ${head:0:12}"

    git fetch -q origin main "$ref" 2>/dev/null || die "git fetch origin main $ref failed"
    git cat-file -e "$new^{commit}" 2>/dev/null || die "the new head ${new:0:12} is not in the clone after the fetch"
    msg="$(bash "$DIR/merge-only-check.sh" "$new" 2>&1)"
    case $? in
        0) CODE=0 out "UPDATED $new" ;;
        1) out "NOT_MERGE_ONLY $new ${msg#NOT_MERGE_ONLY $new }" ;;
        *) die "merge-only-check failed: $msg" ;;
    esac
}

self_test() {
    local tmp fails=0 c res rc r H U X X0 E
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/sleep"; chmod +x "$tmp/bin/sleep"
    . "$DIR/queue-fixtures/scratch-repo.sh"
    # The scratch repo plays GitHub's side: its branches are pushed to a bare `origin`, from which
    # the script fetches. The fake gh serves the PR, compare, PUT and commit answers.
    scratch_repo "$tmp/repo"
    git init -q --bare "$tmp/origin.git"; g remote add origin "$tmp/origin.git"
    br pr main; edit f1 2 pr; H="$(g rev-parse HEAD)"
    main_commit f3 other; gm pr "Merge branch 'main' into chore/pr"; U="$(g rev-parse HEAD)"
    br hand main; edit f1 4 hand; X0="$(g rev-parse HEAD)"; main_commit f8 other
    co hand; g merge -q --no-ff --no-commit main >/dev/null 2>&1
    echo extra >> "$r/f2"; g add f2; g commit -q -m "edited update"; X="$(g rev-parse HEAD)"
    co main; g push -q origin main pr:chore/pr hand:chore/hand
    E="$(printf 'e%.0s' $(seq 40))"
    pr_() { # pr_ <head sha> [<state>] [<base>] [<head repo>] [<head branch>]
        printf '{"state":"%s","base":{"ref":"%s","repo":{"full_name":"o/r"}},"head":{"ref":"%s","sha":"%s","repo":{"full_name":"%s"}}}' \
            "${2:-open}" "${3:-main}" "${5:-chore/pr}" "$1" "${4:-o/r}"
    }
    case_() { c="$tmp/cases/$1"; mkdir -p "$c" "$tmp/state/$1"; }
    put() { printf '%s\n' "$2" > "$c/$1"; }
    run() {
        res="$(cd "$r" && PATH="$tmp/bin:$DIR/queue-fixtures:$PATH" FAKE_GH_DIR="$c" FAKE_GH_STATE="$tmp/state/$(basename "$c")" \
            UPDATE_BRANCH_STEP=1 UPDATE_BRANCH_MAX_SECONDS=3 bash "$SELF" 5 2>&1)" && rc=0 || rc=$?
    }
    expect() { # expect <description> <exit> <output>
        if [ "$rc" = "$2" ] && [ "$res" = "$3" ]; then echo "ok   $1"; else
            echo "FAIL $1: expected exit $2 and '$3', got exit $rc: $res" >&2; fails=$((fails + 1)); fi
    }

    case_ up-to-date; put pr-5.json "$(pr_ "$H")"; put compare-${H:0:7}.json '{"behind_by":0}'
    run; expect "UP_TO_DATE" 0 "UP_TO_DATE $H"
    if grep -q PUT "$tmp/state/up-to-date/log"; then echo "FAIL UP_TO_DATE made a PUT" >&2; fails=$((fails + 1)); else echo "ok   UP_TO_DATE makes no PUT"; fi
    case_ updated; put pr-5-1.json "$(pr_ "$H")"; put pr-5-2.json "$(pr_ "$H")"; put pr-5-3.json "$(pr_ "$U")"
    put compare-${H:0:7}.json '{"behind_by":1}'; put put-5.json '{"message":"Updating pull request branch."}'
    put commit-${U:0:7}.json "{\"parents\":[{\"sha\":\"$H\"},{\"sha\":\"x\"}]}"
    run; expect "UPDATED after GitHub's merge-only update" 0 "UPDATED $U"
    if grep -qxF "api -X PUT repos/{owner}/{repo}/pulls/5/update-branch -f expected_head_sha=$H" "$tmp/state/updated/log"; then
        echo "ok   the PUT carries expected_head_sha"; else echo "FAIL the PUT call:" >&2; cat "$tmp/state/updated/log" >&2; fails=$((fails + 1)); fi
    case_ not-merge-only; put pr-5-1.json "$(pr_ "$X0" open main o/r chore/hand)"; put pr-5-2.json "$(pr_ "$X" open main o/r chore/hand)"
    put compare-${X0:0:7}.json '{"behind_by":1}'; put put-5.json '{}'
    put commit-${X:0:7}.json "{\"parents\":[{\"sha\":\"$X0\"},{\"sha\":\"x\"}]}"
    run; expect "NOT_MERGE_ONLY" 1 "NOT_MERGE_ONLY $X its tree differs from the merge of its parents (edited by hand)"
    case_ conflict; put pr-5.json "$(pr_ "$H")"; put compare-${H:0:7}.json '{"behind_by":2}'
    put put-5.json '{"message":"merge conflict between base and head"}'; put put-5.exit 1; put put-5.stderr "gh: merge conflict between base and head (HTTP 422)"
    run; expect "CONFLICT" 1 "CONFLICT merge conflict between base and head"
    case_ race-put; put pr-5.json "$(pr_ "$H")"; put compare-${H:0:7}.json '{"behind_by":2}'
    put put-5.json "{\"message\":\"expected head sha didn't match current head ref.\"}"; put put-5.exit 1
    run; expect "RACE refused by GitHub" 1 "RACE expected head sha didn't match current head ref."
    case_ workflow; put pr-5.json "$(pr_ "$H")"; put compare-${H:0:7}.json '{"behind_by":2}'
    put put-5.json '{"message":"refusing to allow an OAuth App to create or update workflow `.github/workflows/ci.yml` without `workflow` scope"}'; put put-5.exit 1
    run; expect "REFUSED without workflow scope" 1 'REFUSED refusing to allow an OAuth App to create or update workflow `.github/workflows/ci.yml` without `workflow` scope'
    case_ race-after; put pr-5-1.json "$(pr_ "$H")"; put pr-5-2.json "$(pr_ "$E")"
    put compare-${H:0:7}.json '{"behind_by":1}'; put put-5.json '{}'; put commit-eeeeeee.json "{\"parents\":[{\"sha\":\"$U\"}]}"
    run; expect "RACE: the head moved to something else" 1 "RACE the head of PR #5 moved to ${E:0:12}, which is not an update of ${H:0:12}"
    case_ no-move; put pr-5.json "$(pr_ "$H")"; put compare-${H:0:7}.json '{"behind_by":1}'; put put-5.json '{}'
    run; expect "REFUSED when the head does not move" 1 "REFUSED GitHub accepted the update but the head of PR #5 did not move within 3 s"
    case_ closed; put pr-5.json "$(pr_ "$H" closed)"
    run; expect "REFUSED a closed PR" 1 "REFUSED PR #5 is closed"
    case_ base; put pr-5.json "$(pr_ "$H" open chore/parent)"
    run; expect "REFUSED a base other than main" 1 "REFUSED the base of PR #5 is chore/parent, not main"
    case_ fork; put pr-5.json "$(pr_ "$H" open main someone/r)"
    run; expect "REFUSED a fork's branch" 1 "REFUSED the head of PR #5 is not a branch of this repository"
    case_ gh-fails; run
    [ "$rc" = 2 ] && echo "ok   a failed read exits 2" || { echo "FAIL a failed read: exit $rc: $res" >&2; fails=$((fails + 1)); }
    res="$(bash "$SELF" x 2>&1)"; [ $? = 2 ] && echo "ok   usage error exits 2" || { echo "FAIL usage error does not exit 2" >&2; fails=$((fails + 1)); }
    if [ "$fails" = 0 ]; then echo "update-branch.sh self-test: all passed"; else echo "update-branch.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

[ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }
[ "$1" != --self-test ] || self_test
[[ "$1" =~ ^[0-9]+$ ]] || { echo "$USAGE" >&2; exit 2; }
STEP="${UPDATE_BRANCH_STEP:-5}"
MAX="${UPDATE_BRANCH_MAX_SECONDS:-180}"
[[ "$STEP" =~ ^[1-9][0-9]*$ ]] && [[ "$MAX" =~ ^[0-9]+$ ]] || die "UPDATE_BRANCH_STEP and UPDATE_BRANCH_MAX_SECONDS are whole seconds"
for tool in gh jq git; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"
update "$1"
