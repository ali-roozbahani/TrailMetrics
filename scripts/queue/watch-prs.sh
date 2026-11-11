#!/usr/bin/env bash
# The open PRs of the bot, once or until something happens to one of them: the wait of the PR queue
# (scripts/queue/queue.sh). Run --wait as a background command (`run_in_background`, timeout above
# the wait): the session is re-invoked when it exits.
#
#   scripts/queue/watch-prs.sh --once
#   scripts/queue/watch-prs.sh --wait [<minutes>]      default 180, at most 360
#   scripts/queue/watch-prs.sh --self-test
#
# --once prints one tab-separated line per open PR of the author, then `OPEN <count>` (exit 0):
#   #<number>  <base>  <head branch> <head sha, 12>  open|draft  behind=<commits>  checks=<state>
# checks: running | green | red | missing, read by scripts/wait-for-checks.sh itself (one read, no
# wait: WAIT_FOR_CHECKS_MAX_SECONDS=0) on the head SHA: ALL_GREEN is green, any FAILED line (the
# reviewer's early failure included) is red, TIMEOUT with a check still running is running, TIMEOUT
# with nothing running and a required check absent is missing (a PR whose base is not main gets
# no CI). Behind: `behind_by` of the compare API between the base branch's head and the PR head.
#
# --wait takes the open PRs of its first read as the watched set and exits at the first read that
# shows an event for one of them, printing every event of that read, one per line (exit 0):
#   MERGED #<n> <head branch>          the PR left the open list and is merged
#   CLOSED #<n> <head branch>          the PR left the open list unmerged
#   HEAD_MOVED #<n> <old sha 12> <new sha 12>
#   BEHIND #<n> <commits>              behind_by went from 0 to more (main moved past the PR)
#   CHECKS_DONE green|red #<n> <sha 12>  the checks of the head SHA went from running or missing
#                                        to green or red
# States at the first read are not events (use --once to see them): a PR already behind, or with its
# checks already done, is watched for its merge. A PR opened during the wait is not watched.
#   TIMEOUT open: #<n> ...             the wait ran out; the watched PRs still open     exit 1
#   NONE_OPEN                          --wait found no open PR of the author to watch   exit 3
# Steps: every 30 s for the first 5 minutes, then every 60 s.
#
# REST only (no GraphQL, no `gh pr` commands), GET only, nothing is changed:
#   repos/{owner}/{repo}/pulls?state=open&per_page=100      every read
#   repos/{owner}/{repo}/git/ref/heads/<base>                every read, once per base branch
#   repos/{owner}/{repo}/compare/<base sha>...<head sha>     only when either SHA changed
#   check runs of the head SHA (through wait-for-checks.sh)  only until they are green or red
#   repos/{owner}/{repo}/pulls/<n>                           only when a PR left the open list
# With 5 PRs whose checks are done that is 2 calls a minute; a PR whose checks run adds 1 to 2.
# A failed read is retried: up to 3 failed reads in a row (one step apart); the 4th exits 2.
#
# Environment: WATCH_PRS_AUTHOR (peter-christofer-bot). For the self-test, whole seconds:
#   WATCH_PRS_MAX_SECONDS (overrides <minutes>)  WATCH_PRS_FAST_SECONDS (300)
#   WATCH_PRS_FAST_STEP (30)  WATCH_PRS_SLOW_STEP (60)
# Exit 2: usage error, a missing tool, unreadable data, 4 failed reads in a row. Bash 3.2 compatible.
set -u -o pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
DIR="$(dirname "$SELF")"
WAIT_FOR_CHECKS="$DIR/../wait-for-checks.sh"
AUTHOR="${WATCH_PRS_AUTHOR:-peter-christofer-bot}"
USAGE="usage: scripts/queue/watch-prs.sh --once | --wait [<minutes, 1-360>] | --self-test"

die() { echo "watch-prs: $*" >&2; exit 2; }
usage() { echo "$USAGE" >&2; exit 2; }

elapsed=0
fails=0
next_step() {
    if [ "$elapsed" -lt "$FAST_PHASE" ]; then STEP="$FAST_STEP"; else STEP="$SLOW_STEP"; fi
}
# failed <what>: count a failed read; the 4th in a row exits 2, the others sleep one step.
failed() {
    fails=$((fails + 1))
    [ "$fails" -le 3 ] || die "a read failed $fails times in a row ($1)"
    next_step
    sleep "$STEP"
    elapsed=$((elapsed + STEP))
}
get() { # get <output file> <endpoint>: one GET with retries
    until gh api "$2" > "$1" 2>/dev/null; do failed "$2"; done
    fails=0
}

# checks_of <sha>: running | green | red | missing (cached in $D/checks-<sha> once green or red)
checks_of() {
    local out code last
    if [ -f "$D/checks-$1" ]; then cat "$D/checks-$1"; return; fi
    while :; do
        out="$(WAIT_FOR_CHECKS_MAX_SECONDS=0 bash "$WAIT_FOR_CHECKS" "$1" 2>/dev/null)"
        code=$?
        [ "$code" = 2 ] || break
        failed "the check runs of $1"
    done
    fails=0
    last="$(printf '%s\n' "$out" | tail -1)"
    case "$last" in
        ALL_GREEN) echo green > "$D/checks-$1" ;;
        FAILED*) echo red > "$D/checks-$1" ;;
        "TIMEOUT (none running)"*) echo missing; return ;;
        TIMEOUT*) echo running; return ;;
        *) die "unexpected output of wait-for-checks.sh for $1: $last" ;;
    esac
    cat "$D/checks-$1"
}

# behind_of <base sha> <head sha>: behind_by, cached per pair
behind_of() {
    local f="$D/behind-$1-$2"
    if [ ! -f "$f" ]; then
        get "$D/compare.json" "repos/{owner}/{repo}/compare/$1...$2"
        jq -er '.behind_by | numbers' "$D/compare.json" > "$f" 2>/dev/null || { rm -f "$f"; die "compare data is not readable"; }
    fi
    cat "$f"
}

# read_state <output file>: one line per open PR of the author:
#   number  base  head-ref  head-sha  draft  behind  checks
read_state() {
    local out="$1" number base ref sha draft bsha behind checks
    get "$D/pulls.json" "repos/{owner}/{repo}/pulls?state=open&per_page=100"
    jq -r --arg a "$AUTHOR" '.[] | select(.user.login == $a)
        | [.number, .base.ref, .head.ref, .head.sha, (if .draft then "draft" else "open" end)] | @tsv' \
        "$D/pulls.json" > "$D/list.tsv" 2>/dev/null || die "the PR list is not readable"
    rm -f "$D"/base-*
    : > "$out"
    while IFS="$(printf '\t')" read -r number base ref sha draft; do
        [ -n "$number" ] || continue
        if [ ! -f "$D/base-$base" ]; then
            get "$D/ref.json" "repos/{owner}/{repo}/git/ref/heads/$base"
            jq -er '.object.sha | strings' "$D/ref.json" > "$D/base-$base" 2>/dev/null || die "the ref of $base is not readable"
        fi
        bsha="$(cat "$D/base-$base")"
        behind="$(behind_of "$bsha" "$sha")" || exit 2
        checks="$(checks_of "$sha")" || exit 2
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$number" "$base" "$ref" "$sha" "$draft" "$behind" "$checks" >> "$out"
    done < "$D/list.tsv"
}

once() {
    read_state "$D/now.tsv"
    awk -F '\t' -v OFS='\t' '{ print "#" $1, $2, $3 " " substr($4, 1, 12), $5, "behind=" $6, "checks=" $7 }' "$D/now.tsv"
    echo "OPEN $(grep -c . "$D/now.tsv")"
}

watch() {
    local number base ref sha draft behind checks pn pbase pref psha pdraft pbehind pchecks events open
    read_state "$D/prev.tsv"
    cut -f1,3 "$D/prev.tsv" > "$D/watched.tsv"
    if [ ! -s "$D/watched.tsv" ]; then echo NONE_OPEN; exit 3; fi
    while :; do
        if [ "$elapsed" -ge "$MAX" ]; then
            open="$(cut -f1 "$D/prev.tsv" | sed 's/^/#/' | tr '\n' ' ' | sed 's/ $//')"
            echo "TIMEOUT open: ${open:-(none)}"
            exit 1
        fi
        next_step
        [ "$STEP" -le $((MAX - elapsed)) ] || STEP=$((MAX - elapsed))
        sleep "$STEP"
        elapsed=$((elapsed + STEP))
        read_state "$D/now.tsv"
        events=""
        while IFS="$(printf '\t')" read -r pn pbase pref psha pdraft pbehind pchecks; do
            [ -n "$pn" ] || continue
            if ! IFS="$(printf '\t')" read -r number base ref sha draft behind checks \
                < <(awk -F '\t' -v n="$pn" '$1 == n' "$D/now.tsv") || [ -z "${number:-}" ]; then
                get "$D/pr.json" "repos/{owner}/{repo}/pulls/$pn"
                case "$(jq -r 'if .merged_at then "merged" elif .state == "closed" then "closed" else "open" end' "$D/pr.json" 2>/dev/null)" in
                    merged) events="${events}MERGED #$pn $pref
" ;;
                    closed) events="${events}CLOSED #$pn $pref
" ;;
                    open) ;;  # left the author's list but still open: not ours to judge, keep watching
                    *) die "PR $pn is not readable" ;;
                esac
                continue
            fi
            if [ "$sha" != "$psha" ]; then
                events="${events}HEAD_MOVED #$pn ${psha:0:12} ${sha:0:12}
"
                continue
            fi
            if [ "$pbehind" = 0 ] && [ "$behind" != 0 ]; then events="${events}BEHIND #$pn $behind
"; fi
            case "$pchecks:$checks" in
                running:green | missing:green) events="${events}CHECKS_DONE green #$pn ${sha:0:12}
" ;;
                running:red | missing:red) events="${events}CHECKS_DONE red #$pn ${sha:0:12}
" ;;
            esac
        done < "$D/prev.tsv"
        if [ -n "$events" ]; then printf '%s' "$events"; exit 0; fi
        # keep only the watched PRs, with their newest state
        awk -F '\t' 'NR == FNR { w[$1] = 1; next } ($1 in w)' "$D/watched.tsv" "$D/now.tsv" > "$D/prev.tsv"
    done
}

self_test() {
    local tmp fails=0 c out rc A B C2 G R RUN MISS
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    A="aaaaaaa$(printf '1%.0s' $(seq 33))"; B="bbbbbbb$(printf '2%.0s' $(seq 33))"; C2="ccccccc$(printf '3%.0s' $(seq 33))"
    M1="ddddddd$(printf '4%.0s' $(seq 33))"; M2="eeeeeee$(printf '5%.0s' $(seq 33))"
    run_() { printf '{"name":"%s","status":"%s","conclusion":%s,"head_sha":"x","id":1}' "$1" "$2" "$3"; }
    G="{\"check_runs\":[$(run_ 'Android — Lint, Detekt, Tests, Build' completed '"success"'),$(run_ 'iOS — all stages' completed '"success"'),$(run_ 'Repo tooling — policy checks and script self-tests' completed '"success"'),$(run_ 'Review — pr-reviewer' completed '"success"')]}"
    R="{\"check_runs\":[$(run_ 'Android — Lint, Detekt, Tests, Build' completed '"success"'),$(run_ 'iOS — all stages' completed '"failure"'),$(run_ 'Repo tooling — policy checks and script self-tests' completed '"success"'),$(run_ 'Review — pr-reviewer' completed '"success"')]}"
    RUN="{\"check_runs\":[$(run_ 'Android — Lint, Detekt, Tests, Build' in_progress null),$(run_ 'iOS — all stages' completed '"success"'),$(run_ 'Repo tooling — policy checks and script self-tests' completed '"success"'),$(run_ 'Review — pr-reviewer' completed '"success"')]}"
    MISS='{"check_runs":[]}'
    pr_() { # pr_ <number> <head sha> [<author>] [<base>]
        printf '{"number":%s,"user":{"login":"%s"},"base":{"ref":"%s"},"head":{"ref":"chore/pr-%s","sha":"%s"},"draft":false}' \
            "$1" "${3:-peter-christofer-bot}" "${4:-main}" "$1" "$2"
    }
    case_() { c="$tmp/cases/$1"; mkdir -p "$c" "$tmp/state/$1"; }
    # The steps are counted, not timed: a no-op `sleep` keeps the self-test fast.
    mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/sleep"; chmod +x "$tmp/bin/sleep"
    put() { printf '%s\n' "$2" > "$c/$1"; }   # put <file> <content>
    run() { # run <args...>: the script against case $c
        out="$(PATH="$tmp/bin:$DIR/queue-fixtures:$PATH" FAKE_GH_DIR="$c" FAKE_GH_STATE="$tmp/state/$(basename "$c")" \
            WATCH_PRS_MAX_SECONDS="${MAXS:-6}" WATCH_PRS_FAST_SECONDS=2 WATCH_PRS_FAST_STEP=1 WATCH_PRS_SLOW_STEP=2 \
            bash "$SELF" "$@" 2>&1)" && rc=0 || rc=$?
    }
    expect() { # expect <description> <expected exit> <expected output>
        if [ "$rc" = "$2" ] && [ "$out" = "$3" ]; then echo "ok   $1"; else
            echo "FAIL $1: expected exit $2 and:" >&2; printf '%s\n' "$3" | sed 's/^/       /' >&2
            echo "     got exit $rc and:" >&2; printf '%s\n' "$out" | sed 's/^/       /' >&2; fails=$((fails + 1)); fi
    }
    base_() { put ref-main.json "{\"object\":{\"sha\":\"$M1\"}}"; }

    # --once: every checks state, behind, draft, another author's PR left out
    case_ once; base_
    put pulls.json "[$(pr_ 1 "$A"),$(pr_ 2 "$B"),$(pr_ 3 "$C2"),$(pr_ 9 "$M2" someone)]"
    put compare-aaaaaaa.json '{"behind_by":0}'; put compare-bbbbbbb.json '{"behind_by":3}'; put compare-ccccccc.json '{"behind_by":0}'
    put checks-aaaaaaa.json "$G"; put checks-bbbbbbb.json "$RUN"; put checks-ccccccc.json "$MISS"
    run --once
    expect "--once lists the author's PRs" 0 "#1	main	chore/pr-1 ${A:0:12}	open	behind=0	checks=green
#2	main	chore/pr-2 ${B:0:12}	open	behind=3	checks=running
#3	main	chore/pr-3 ${C2:0:12}	open	behind=0	checks=missing
OPEN 3"
    case_ once-red; base_; put pulls.json "[$(pr_ 4 "$A")]"; put compare-aaaaaaa.json '{"behind_by":0}'; put checks-aaaaaaa.json "$R"
    run --once; expect "--once red checks" 0 "#4	main	chore/pr-4 ${A:0:12}	open	behind=0	checks=red
OPEN 1"

    # --wait events
    case_ merged; base_; put pulls-1.json "[$(pr_ 1 "$A"),$(pr_ 2 "$B")]"; put pulls-3.json "[$(pr_ 2 "$B")]"
    put compare-aaaaaaa.json '{"behind_by":0}'; put compare-bbbbbbb.json '{"behind_by":0}'
    put checks-aaaaaaa.json "$G"; put checks-bbbbbbb.json "$G"; put pr-1.json '{"state":"closed","merged_at":"2026-11-11T10:00:00Z"}'
    run --wait; expect "MERGED" 0 "MERGED #1 chore/pr-1"
    case_ closed; base_; put pulls-1.json "[$(pr_ 1 "$A")]"; put pulls-2.json "[]"
    put compare-aaaaaaa.json '{"behind_by":0}'; put checks-aaaaaaa.json "$G"; put pr-1.json '{"state":"closed","merged_at":null}'
    run --wait; expect "CLOSED" 0 "CLOSED #1 chore/pr-1"
    case_ behind; put ref-main-1.json "{\"object\":{\"sha\":\"$M1\"}}"; put ref-main-3.json "{\"object\":{\"sha\":\"$M2\"}}"
    put pulls.json "[$(pr_ 1 "$A")]"; put compare-aaaaaaa-1.json '{"behind_by":0}'; put compare-aaaaaaa-2.json '{"behind_by":1}'; put checks-aaaaaaa.json "$G"
    run --wait; expect "BEHIND when main moves past the PR" 0 "BEHIND #1 1"
    case_ moved; base_; put pulls-1.json "[$(pr_ 1 "$A")]"; put pulls-2.json "[$(pr_ 1 "$B")]"
    put compare-aaaaaaa.json '{"behind_by":0}'; put compare-bbbbbbb.json '{"behind_by":0}'; put checks-aaaaaaa.json "$RUN"; put checks-bbbbbbb.json "$RUN"
    run --wait; expect "HEAD_MOVED" 0 "HEAD_MOVED #1 ${A:0:12} ${B:0:12}"
    case_ green; base_; put pulls.json "[$(pr_ 1 "$A")]"; put compare-aaaaaaa.json '{"behind_by":0}'
    put checks-aaaaaaa-1.json "$MISS"; put checks-aaaaaaa-2.json "$RUN"; put checks-aaaaaaa-3.json "$G"
    run --wait; expect "CHECKS_DONE green" 0 "CHECKS_DONE green #1 ${A:0:12}"
    case_ red; base_; put pulls.json "[$(pr_ 1 "$A")]"; put compare-aaaaaaa.json '{"behind_by":0}'
    put checks-aaaaaaa-1.json "$RUN"; put checks-aaaaaaa-2.json "$R"
    run --wait; expect "CHECKS_DONE red" 0 "CHECKS_DONE red #1 ${A:0:12}"
    case_ two; base_; put pulls-1.json "[$(pr_ 1 "$A"),$(pr_ 2 "$B")]"; put pulls-2.json "[$(pr_ 2 "$B")]"
    put compare-aaaaaaa.json '{"behind_by":0}'; put compare-bbbbbbb.json '{"behind_by":0}'
    put checks-aaaaaaa.json "$G"; put checks-bbbbbbb-1.json "$RUN"; put checks-bbbbbbb-2.json "$G"; put pr-1.json '{"state":"closed","merged_at":"x"}'
    run --wait; expect "two events of one read" 0 "MERGED #1 chore/pr-1
CHECKS_DONE green #2 ${B:0:12}"
    case_ timeout; base_; put pulls.json "[$(pr_ 1 "$A"),$(pr_ 2 "$B")]"; put compare-aaaaaaa.json '{"behind_by":2}'; put compare-bbbbbbb.json '{"behind_by":0}'
    put checks-aaaaaaa.json "$G"; put checks-bbbbbbb.json "$MISS"
    run --wait; expect "TIMEOUT; states of the first read are no events" 1 "TIMEOUT open: #1 #2"
    if [ "$(grep -c '/check-runs' "$tmp/state/timeout/log")" -ge 4 ] && [ "$(grep -c 'commits/aaaaaaa.*check-runs' "$tmp/state/timeout/log")" = 1 ] \
        && [ "$(grep -c '/compare/' "$tmp/state/timeout/log")" = 2 ]; then echo "ok   done checks and an unchanged compare are read once"
    else echo "FAIL the REST reads are not cached:" >&2; sed 's/^/       /' "$tmp/state/timeout/log" >&2; fails=$((fails + 1)); fi
    if grep -qv '^api repos/{owner}/{repo}/' "$tmp/state/timeout/log"; then echo "FAIL a call that is not a REST GET" >&2; fails=$((fails + 1)); else echo "ok   REST GET reads only"; fi
    case_ newpr; base_; put pulls-1.json "[$(pr_ 1 "$A")]"; put pulls-2.json "[$(pr_ 1 "$A"),$(pr_ 2 "$B")]"
    put compare-aaaaaaa.json '{"behind_by":0}'; put compare-bbbbbbb.json '{"behind_by":0}'; put checks-aaaaaaa.json "$G"; put checks-bbbbbbb-1.json "$RUN"; put checks-bbbbbbb-2.json "$G"
    run --wait; expect "a PR opened during the wait is not watched" 1 "TIMEOUT open: #1"
    case_ none; base_; put pulls.json "[$(pr_ 9 "$A" someone)]"
    run --wait; expect "NONE_OPEN" 3 "NONE_OPEN"
    case_ flaky; base_; put pulls.json "[$(pr_ 1 "$A")]"; put compare-aaaaaaa.json '{"behind_by":0}'; put checks-aaaaaaa.json "$G"
    put pulls.exit 1; put pulls.stderr "gh: boom"
    run --once; [ "$rc" = 2 ] && case "$out" in *"failed 4 times in a row"*) true ;; *) false ;; esac \
        && echo "ok   4 failed reads in a row exit 2" || { echo "FAIL 4 failed reads: exit $rc: $out" >&2; fails=$((fails + 1)); }
    case_ flaky3; base_; put pulls.json "[$(pr_ 1 "$A")]"; put compare-aaaaaaa.json '{"behind_by":0}'; put checks-aaaaaaa.json "$G"
    put pulls.fail-calls "1 2 3"; put compare-aaaaaaa.fail-calls "1"
    run --once; expect "3 failed reads in a row are retried" 0 "#1	main	chore/pr-1 ${A:0:12}	open	behind=0	checks=green
OPEN 1"

    for a in "" "--wait 0" "--wait 361" "--wait x" "--once 3" "--bogus"; do
        out="$(bash "$SELF" $a 2>&1)"; rc=$?
        [ "$rc" = 2 ] && echo "ok   usage error: '$a'" || { echo "FAIL '$a' does not exit 2 ($rc)" >&2; fails=$((fails + 1)); }
    done
    if [ "$fails" = 0 ]; then echo "watch-prs.sh self-test: all passed"; else echo "watch-prs.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

MODE=""
MINUTES=180
case "${1:-}" in
    --self-test) [ "$#" = 1 ] || usage; self_test ;;
    --once) [ "$#" = 1 ] || usage; MODE=once ;;
    --wait)
        [ "$#" -le 2 ] || usage
        MODE=wait
        if [ "$#" = 2 ]; then MINUTES="$2"; fi
        [[ "$MINUTES" =~ ^[0-9]+$ ]] && [ "$MINUTES" -ge 1 ] && [ "$MINUTES" -le 360 ] || usage ;;
    *) usage ;;
esac
MAX="${WATCH_PRS_MAX_SECONDS:-$((MINUTES * 60))}"
FAST_PHASE="${WATCH_PRS_FAST_SECONDS:-300}"
FAST_STEP="${WATCH_PRS_FAST_STEP:-30}"
SLOW_STEP="${WATCH_PRS_SLOW_STEP:-60}"
for v in "$MAX" "$FAST_PHASE" "$FAST_STEP" "$SLOW_STEP"; do
    [[ "$v" =~ ^[0-9]+$ ]] || die "the WATCH_PRS_* times are whole seconds"
done
[ "$FAST_STEP" -ge 1 ] && [ "$SLOW_STEP" -ge 1 ] || die "the WATCH_PRS_*_STEP times must be at least 1 second"
for tool in gh jq; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
D="$(mktemp -d)"
trap 'rm -rf -- "$D"' EXIT
if [ "$MODE" = once ]; then once; else watch; fi
