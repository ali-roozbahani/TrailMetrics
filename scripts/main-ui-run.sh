#!/usr/bin/env bash
# The full UI run on main: both platforms' whole UI suites on the current `origin/main`, outside any PR. The
# gate runs the suites of the platforms a branch touches; this run catches what a merge of several PRs, or a
# change the gate's scope map missed, can break. It is decided by this script, not by memory:
#
#   scripts/main-ui-run.sh --auto           run when due, else print why not (the form the agent loop calls)
#   scripts/main-ui-run.sh --due            exit 0 and `DUE <reason>`, exit 3 and `NOT_DUE <reason>`
#   scripts/main-ui-run.sh --status         the last full run and whether one is due (never fails the caller)
#   scripts/main-ui-run.sh --run            run now, due or not
#   scripts/main-ui-run.sh --release        before a release: run when due, then exit 0 only when the full run
#                                           of the current main is green
#   scripts/main-ui-run.sh --self-test
#
# When it is due (owner decision of 2026-11-15, step 3):
#   - the queue has become empty and main has code changes since the last full run, or no run is recorded;
#     `--auto` is what tm-agent-loop (section 9) runs at the queue's `DONE`, and `--status` is a line of the
#     start of every task, so a run that was due when a session ended is not forgotten;
#   - before every release (`--release`; nothing in this repository releases yet, so a release step has to call it).
# "Code changes" is the classifier's answer (`scripts/classify-changes.sh --ui-scope --base <last SHA>`): anything
# but `none` (docs, skills and tooling scripts) is due. The SHA of the last full run, its result and the result of
# each suite are kept in ${TM_MAIN_UI_STATE:-~/agent-workspace/main-ui-last-run}, one line, red runs included: main
# at a red run's SHA is not run again (it is the queue's entry now), and the next merge makes a run due.
#
# A run needs the clone on a clean `main` that equals `origin/main` (the iOS secrets config lives in this clone),
# fetches first, runs scripts/android-ui-tests.sh and scripts/ios-ui-tests.sh in that order under heavy-run and the
# gate's time limits, runs both even when the first is red, and has no retry: red is red (tm-testing). A red run
# keeps both logs (~/agent-workspace/keep-main-ui-<sha>-<suite>.log) and adds the entry
# `main-ui-red-<sha>` (bugfix/ branch, agent) to the queue, where it is the first entry because the queue is empty
# when the run happens; it says what failed and that a flake is logged in CI_FLAKES.md, not retried.
#
# Exit: 0 (green, or not due for --auto), 1 (red, or --release without a green run), 2 (the clone is not on a
# clean, synced main, or an environment problem), 3 (--due: not due).
# Bash 3.2 compatible.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
STATE="${TM_MAIN_UI_STATE:-$HOME/agent-workspace/main-ui-last-run}"
LOG_DIR="${TM_MAIN_UI_LOG_DIR:-$HOME/agent-workspace}"
ANDROID_LIMIT=420   # the gate's limits (scripts/pre-push-check.sh)
IOS_LIMIT=720

die() { echo "main-ui-run: $*" >&2; exit 2; }

short() { printf '%s' "${1:0:8}"; }

# Prints a reason and returns 1 unless the clone is on a clean main that equals origin/main (after a fetch).
require_synced_main() {
    local branch
    git -C "$ROOT" fetch -q origin main 2>/dev/null || { SYNC_PROBLEM="git fetch origin main failed"; return 1; }
    branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    [ "$branch" = main ] || { SYNC_PROBLEM="the clone is on '$branch', not on main"; return 1; }
    [ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || { SYNC_PROBLEM="the working tree is not clean"; return 1; }
    [ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" ] \
        || { SYNC_PROBLEM="main is not at origin/main (git pull --ff-only)"; return 1; }
    return 0
}

read_state() { # sets LAST_SHA, LAST_RESULT, LAST_TIME, LAST_ANDROID, LAST_IOS (empty when there is no state)
    LAST_SHA=""; LAST_RESULT=""; LAST_TIME=""; LAST_ANDROID=""; LAST_IOS=""
    [ -f "$STATE" ] || return 0
    read -r LAST_SHA LAST_RESULT LAST_TIME LAST_ANDROID LAST_IOS < "$STATE" || true
}

# Decides whether a run is due. Needs a synced main. Prints `DUE <reason>` or `NOT_DUE <reason>`; returns 0, 3, or 2.
decide() {
    local head scope
    require_synced_main || { echo "UNKNOWN $SYNC_PROBLEM"; return 2; }
    head="$(git -C "$ROOT" rev-parse HEAD)"
    read_state
    if [ -z "$LAST_SHA" ]; then echo "DUE no full run is recorded"; return 0; fi
    if [ "$LAST_SHA" = "$head" ]; then
        echo "NOT_DUE main is at the last full run ($(short "$head"), $LAST_RESULT)"
        return 3
    fi
    if ! git -C "$ROOT" cat-file -e "$LAST_SHA^{commit}" 2>/dev/null; then
        echo "DUE the last full run's commit $(short "$LAST_SHA") is not in this clone"
        return 0
    fi
    scope="$("$ROOT/scripts/classify-changes.sh" --root "$ROOT" --ui-scope --base "$LAST_SHA" 2>/dev/null | head -n 1)"
    case "$scope" in
        'ui-scope: none')
            echo "NOT_DUE only docs, skills and tooling scripts changed since the last full run ($(short "$LAST_SHA"), $LAST_RESULT)"
            return 3 ;;
        'ui-scope: '*)
            echo "DUE code changed since the last full run ($(short "$LAST_SHA"), $LAST_RESULT): $scope"
            return 0 ;;
        *)
            echo "DUE the classifier gave no ui-scope since $(short "$LAST_SHA")"
            return 0 ;;
    esac
}

run_suite() { # <label> <limit> <script> <logfile>: prints pass or fail
    local label="$1" limit="$2" script="$3" log="$4" status
    echo "main-ui-run: $label ..." >&2
    "$ROOT/scripts/heavy-run.sh" "$ROOT/scripts/run-limited.sh" "$limit" "$ROOT/scripts/$script" >"$log" 2>&1
    status=$?
    if [ "$status" -eq 0 ]; then echo pass; else echo "fail"; echo "main-ui-run: $label failed (status $status), log $log" >&2; fi
    return 0
}

add_red_entry() { # <sha> <android> <ios> <logs...>
    local sha="$1" android="$2" ios="$3" slug task failing
    slug="main-ui-red-$(short "$sha" | cut -c1-7)"
    task="$LOG_DIR/task-$slug.md"
    failing=""
    [ "$android" = pass ] || failing="$failing Android"
    [ "$ios" = pass ] || failing="$failing iOS"
    {
        echo "The full UI run on main at $sha is red:$failing (Android: $android, iOS: $ios)."
        echo
        echo "Logs (kept): $LOG_DIR/keep-main-ui-$(short "$sha")-android.log and $LOG_DIR/keep-main-ui-$(short "$sha")-ios.log."
        echo "Find the cause with the logs and the commits since the previous full run, then fix it, or, when no change of"
        echo "ours explains it, log the failure in CI_FLAKES.md (tm-pr-workflow, \"Flake log\"). No retry of the run to make"
        echo "it green: the rule is tm-testing's, red is red. A fix is a bugfix/ PR through the gate like any other; its"
        echo "gate runs the UI tests of the platform it touches."
    } > "$task"
    if "$ROOT/scripts/queue/queue.sh" add "$slug" --branch "bugfix/$slug" --kind agent --task "$task" >&2; then
        echo "main-ui-run: queue entry $slug added (the first entry: the queue is empty when this run happens)" >&2
    else
        echo "main-ui-run: could NOT add the queue entry $slug (see above): report the red run and add it by hand" >&2
    fi
}

do_run() {
    local sha started android ios result tmpstate
    require_synced_main || die "$SYNC_PROBLEM: no run"
    sha="$(git -C "$ROOT" rev-parse HEAD)"
    mkdir -p "$LOG_DIR" || die "cannot create $LOG_DIR"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "main-ui-run: full UI run on main at $sha ($started)"
    android="$(run_suite "Android UI tests" "$ANDROID_LIMIT" android-ui-tests.sh "$LOG_DIR/keep-main-ui-$(short "$sha")-android.log")"
    ios="$(run_suite "iOS UI tests" "$IOS_LIMIT" ios-ui-tests.sh "$LOG_DIR/keep-main-ui-$(short "$sha")-ios.log")"
    result=green
    [ "$android" = pass ] && [ "$ios" = pass ] || result=red
    mkdir -p "$(dirname "$STATE")" && tmpstate="$STATE.tmp.$$" \
        && printf '%s %s %s android=%s ios=%s\n' "$sha" "$result" "$started" "$android" "$ios" > "$tmpstate" \
        && mv "$tmpstate" "$STATE" || die "cannot write the state file $STATE"
    echo "main-ui-run: Android $android, iOS $ios: $result at $(short "$sha")"
    if [ "$result" = green ]; then
        rm -f "$LOG_DIR/keep-main-ui-$(short "$sha")-android.log" "$LOG_DIR/keep-main-ui-$(short "$sha")-ios.log"
        return 0
    fi
    add_red_entry "$sha" "$android" "$ios"
    return 1
}

cmd_auto() {
    local out rc
    out="$(decide)"; rc=$?
    echo "$out"
    case "$rc" in
        0) do_run ;;
        3) return 0 ;;
        *) return 2 ;;
    esac
}

cmd_release() {
    local out rc
    out="$(decide)"; rc=$?
    echo "$out"
    case "$rc" in
        0) do_run || { echo "main-ui-run: no release: the full UI run is red"; return 1; } ;;
        3) ;;
        *) return 2 ;;
    esac
    read_state
    if [ "$LAST_RESULT" = green ]; then
        echo "main-ui-run: release allowed: the last full UI run ($(short "$LAST_SHA")) is green and nothing that needs one changed since"
        return 0
    fi
    echo "main-ui-run: no release: the last full UI run ($(short "$LAST_SHA")) is ${LAST_RESULT:-missing}"
    return 1
}

cmd_status() {
    read_state
    if [ -n "$LAST_SHA" ]; then echo "last full UI run on main: $(short "$LAST_SHA") $LAST_RESULT at $LAST_TIME ($LAST_ANDROID $LAST_IOS)"
    else echo "last full UI run on main: none recorded"; fi
    decide || true
    return 0
}

self_test() {
    local tmp fails=0 out rc
    tmp="$(mktemp -d)" || return 1
    trap 'rm -rf "$tmp"' RETURN
    local origin="$tmp/origin.git" clone="$tmp/clone"
    git init -q --bare -b main "$origin"
    git clone -q "$origin" "$clone" 2>/dev/null
    git -C "$clone" config user.email t@example.invalid; git -C "$clone" config user.name t
    mkdir -p "$clone/scripts/queue" "$clone/androidApp" "$clone/docs"
    cp "$SELF" "$clone/scripts/main-ui-run.sh"
    cp "$ROOT/scripts/classify-changes.sh" "$clone/scripts/classify-changes.sh"
    cp "$ROOT/scripts/run-limited.sh" "$clone/scripts/run-limited.sh"
    printf '#!/usr/bin/env bash\nexec "$@"\n' > "$clone/scripts/heavy-run.sh"
    for s in android ios; do
        printf '#!/usr/bin/env bash\necho ran >> "$TM_TEST_RAN"\n[ "${TM_TEST_FAIL:-}" = %s ] && exit 1\nexit 0\n' "$s" > "$clone/scripts/$s-ui-tests.sh"
    done
    printf '#!/usr/bin/env bash\necho "$@" >> "$TM_TEST_QUEUE"\nexit 0\n' > "$clone/scripts/queue/queue.sh"
    chmod +x "$clone"/scripts/*.sh "$clone"/scripts/queue/queue.sh
    echo base > "$clone/README.md"
    git -C "$clone" add -A && git -C "$clone" commit -q -m base && git -C "$clone" push -q origin main 2>/dev/null
    local run="$clone/scripts/main-ui-run.sh"
    export TM_MAIN_UI_STATE="$tmp/state" TM_MAIN_UI_LOG_DIR="$tmp/logs" TM_TEST_RAN="$tmp/ran" TM_TEST_QUEUE="$tmp/queue"
    : > "$TM_TEST_RAN"; : > "$TM_TEST_QUEUE"

    t() { # name wanted-exit wanted-fragment command...
        local name="$1" want="$2" frag="$3"
        shift 3
        out="$("$@" 2>&1)"; rc=$?
        if [ "$rc" -eq "$want" ] && { [ -z "$frag" ] || printf '%s' "$out" | grep -qF -- "$frag"; }; then
            echo "ok   $name (exit $rc)"
        else
            echo "FAIL $name: wanted exit $want${frag:+ and \"$frag\"}, got $rc: $out"; fails=$((fails + 1))
        fi
    }
    commit() { printf '%s\n' "$2" >> "$clone/$1"; git -C "$clone" add -A && git -C "$clone" commit -q -m "$1" && git -C "$clone" push -q origin main 2>/dev/null; }
    ran() { wc -l < "$TM_TEST_RAN" | tr -d ' '; }

    t "no run recorded: due" 0 "DUE no full run is recorded" "$run" --due
    t "--auto runs both suites when due" 0 "Android pass, iOS pass: green" "$run" --auto
    [ "$(ran)" = 2 ] && echo "ok   both suites ran (2)" || { echo "FAIL suites ran: $(ran), wanted 2"; fails=$((fails + 1)); }
    grep -q "^$(git -C "$clone" rev-parse HEAD) green " "$TM_MAIN_UI_STATE" && echo "ok   the state names HEAD and green" || { echo "FAIL state: $(cat "$TM_MAIN_UI_STATE" 2>&1)"; fails=$((fails + 1)); }
    t "a green run leaves no kept logs" 0 "" sh -c "! ls '$tmp/logs'/keep-main-ui-* >/dev/null 2>&1"
    t "main at the last run: not due" 3 "NOT_DUE main is at the last full run" "$run" --due
    commit docs/a.md "docs only"
    t "only docs since the run: not due" 3 "NOT_DUE only docs, skills and tooling scripts" "$run" --due
    t "--auto when not due runs nothing" 0 "NOT_DUE" "$run" --auto
    [ "$(ran)" = 2 ] && echo "ok   nothing ran for a docs-only change" || { echo "FAIL ran $(ran)"; fails=$((fails + 1)); }
    commit androidApp/X.kt "code"
    t "a code change since the run: due" 0 "DUE code changed since the last full run" "$run" --due
    t "--release runs the due run first and allows a green one" 0 "release allowed" "$run" --release
    [ "$(ran)" = 4 ] && echo "ok   --release ran both suites (4 in all)" || { echo "FAIL ran $(ran), wanted 4"; fails=$((fails + 1)); }
    commit androidApp/Y.kt "more code"
    export TM_TEST_FAIL=android
    t "a red Android suite: exit 1, both suites ran" 1 "Android fail, iOS pass: red" "$run" --auto
    [ "$(ran)" = 6 ] && echo "ok   the iOS suite ran after the red Android one" || { echo "FAIL ran $(ran), wanted 6"; fails=$((fails + 1)); }
    grep -q "^$(git -C "$clone" rev-parse HEAD) red " "$TM_MAIN_UI_STATE" && echo "ok   the state names HEAD and red" || { echo "FAIL state: $(cat "$TM_MAIN_UI_STATE")"; fails=$((fails + 1)); }
    local sha7; sha7="$(git -C "$clone" rev-parse HEAD | cut -c1-7)"
    grep -q "add main-ui-red-$sha7 --branch bugfix/main-ui-red-$sha7 --kind agent" "$TM_TEST_QUEUE" \
        && echo "ok   the red run added the queue entry main-ui-red-$sha7" || { echo "FAIL queue calls: $(cat "$TM_TEST_QUEUE")"; fails=$((fails + 1)); }
    t "a red run keeps its logs" 0 "" sh -c "ls '$tmp/logs'/keep-main-ui-*-android.log >/dev/null"
    unset TM_TEST_FAIL
    t "main at a red run's SHA is not run again" 3 "(" "$run" --due
    t "--release refuses while the last run is red" 1 "no release" "$run" --release
    git -C "$clone" switch -q -c topic
    t "not on main: exit 2" 2 "not on main" "$run" --run
    git -C "$clone" switch -q main
    echo dirty >> "$clone/README.md"
    t "a dirty tree: exit 2" 2 "not clean" "$run" --run
    git -C "$clone" checkout -q -- README.md
    t "--status never fails" 0 "last full UI run on main" "$run" --status
    t "an unknown option is a usage error" 2 "usage" "$run" --nonsense
    if [ "$fails" -eq 0 ]; then echo "main-ui-run self-test: all cases passed"; return 0; fi
    echo "main-ui-run self-test: $fails case(s) failed" >&2
    return 1
}

usage() { sed -n '2,12p' "$SELF" >&2; echo "usage: scripts/main-ui-run.sh --auto | --due | --status | --run | --release | --self-test" >&2; exit 2; }

case "${1:-}" in
    --auto) cmd_auto ;;
    --due) out="$(decide)"; rc=$?; echo "$out"; exit "$rc" ;;
    --status) cmd_status ;;
    --run) do_run ;;
    --release) cmd_release ;;
    --self-test) self_test ;;
    *) usage ;;
esac
