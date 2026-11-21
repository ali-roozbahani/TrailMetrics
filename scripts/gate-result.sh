#!/usr/bin/env bash
# Reads the result of a gate run from the gate's own output, and from nothing else.
#
#   scripts/gate-result.sh <gate output file> [<expected HEAD sha>]
#   scripts/gate-result.sh --self-test
#
# scripts/pre-push-check.sh ends every run, passed or failed or refused early, with one line
# `GATE_EXIT <n> HEAD <40-hex sha>` (its EXIT trap: the exit code the gate process really has, and the commit it
# gated). That line is the result. The exit code of whatever started the gate is not: a background task, a
# `( gate > log; echo ... )` group or a pipe reports its own last command, and in the first epic run a wrapper's
# "exit code 0" was read as the gate's `exit 1` and a subtask was merged on it. A line a wrapper wrote itself
# (`GATE_EXIT 1` with no HEAD field) is ignored for the same reason.
#
# Prints `GATE_PASS <sha>`, `GATE_FAIL <n> <sha>` or `GATE_UNKNOWN <why>`, and exits 0 (passed), 1 (failed) or
# 3 (no result: the gate is still running, was killed, or the file has no gate line; never a pass). With an expected
# sha, a result for another commit is GATE_UNKNOWN (exit 3). Usage error: exit 2.
# Bash 3.2 compatible.
set -u
USAGE="usage: scripts/gate-result.sh <gate output file> [<expected HEAD sha>] | --self-test"

result() {
    local file="$1" want="${2:-}" line code sha
    [ -r "$file" ] || { echo "GATE_UNKNOWN cannot read $file"; return 3; }
    line="$(grep -E '^GATE_EXIT [0-9]+ HEAD [0-9a-f]{40}$' "$file" | tail -n 1)"
    [ -n "$line" ] || { echo "GATE_UNKNOWN no 'GATE_EXIT <n> HEAD <sha>' line in $file (still running, killed, or not a gate output)"; return 3; }
    code="$(printf '%s\n' "$line" | awk '{print $2}')"
    sha="$(printf '%s\n' "$line" | awk '{print $4}')"
    if [ -n "$want" ] && [ "$want" != "$sha" ]; then
        echo "GATE_UNKNOWN the gate line is for $sha, not for $want"; return 3
    fi
    if [ "$code" = 0 ]; then echo "GATE_PASS $sha"; return 0; fi
    echo "GATE_FAIL $code $sha"; return 1
}

self_test() {
    local tmp fails=0 out rc sha other
    tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
    sha=1111111111111111111111111111111111111111; other=2222222222222222222222222222222222222222
    check() { # check <description> <expected output> <expected exit> <file> [sha]
        out="$(result "$4" "${5:-}")"; rc=$?
        if [ "$out" = "$2" ] && [ "$rc" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got exit $rc '$out', want exit $3 '$2'" >&2; fails=$((fails + 1)); fi
    }
    printf 'ok step\nAll required checks passed.\nGATE_EXIT 0 HEAD %s\n' "$sha" > "$tmp/pass"
    printf 'FAIL step\nGATE_EXIT 1 HEAD %s\n' "$sha" > "$tmp/fail"
    printf 'step\nstep\n' > "$tmp/running"
    printf 'FAIL step\nGATE_EXIT 1 HEAD %s\nGATE_EXIT 0\n' "$sha" > "$tmp/wrapper"
    printf 'GATE_EXIT 0 HEAD %s\nGATE_EXIT 1 HEAD %s\n' "$sha" "$sha" > "$tmp/twice"
    check "a passed gate" "GATE_PASS $sha" 0 "$tmp/pass"
    check "a failed gate" "GATE_FAIL 1 $sha" 1 "$tmp/fail"
    check "no gate line is no result" "GATE_UNKNOWN no 'GATE_EXIT <n> HEAD <sha>' line in $tmp/running (still running, killed, or not a gate output)" 3 "$tmp/running"
    check "a wrapper's own line is ignored (the gate failed)" "GATE_FAIL 1 $sha" 1 "$tmp/wrapper"
    check "the last gate line counts" "GATE_FAIL 1 $sha" 1 "$tmp/twice"
    check "a result for the expected commit" "GATE_PASS $sha" 0 "$tmp/pass" "$sha"
    check "a result for another commit is no result" "GATE_UNKNOWN the gate line is for $sha, not for $other" 3 "$tmp/pass" "$other"
    check "a missing file is no result" "GATE_UNKNOWN cannot read $tmp/none" 3 "$tmp/none"
    out="$(bash "$0" 2>&1)"; rc=$?
    if [ "$rc" = 2 ]; then echo "ok   usage error exits 2"; else echo "FAIL usage error: exit $rc" >&2; fails=$((fails + 1)); fi
    if [ "$fails" = 0 ]; then echo "gate-result.sh self-test: all passed"; else echo "gate-result.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]; exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    "" | -*) echo "$USAGE" >&2; exit 2 ;;
    *) [ "$#" -le 2 ] || { echo "$USAGE" >&2; exit 2; }; result "$@"; exit $? ;;
esac
