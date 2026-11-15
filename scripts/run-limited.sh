#!/usr/bin/env bash
# Runs a command with a hard time limit for the whole run, killing its process group when the limit is hit.
#
#   scripts/run-limited.sh <seconds> <command> [args...]
#   scripts/run-limited.sh --self-test
#
# macOS has no `timeout`, so a small perl wrapper runs the command in its own process group and kills the
# group (xcodebuild, Gradle, the emulator, the simulator's test runner) when the alarm fires. Exit status:
# the command's; 124 when the limit was hit; 130, 143 or 129 after Ctrl-C (INT), TERM or HUP, which reach only
# the caller's own group, so the wrapper catches them and kills the command's group the same way (signals are
# blocked until the child's pid is known); 127 when the command could not be started; 2 for a usage error.
# The gate (scripts/pre-push-check.sh) and scripts/main-ui-run.sh run their UI-test steps through it.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

run_limited() {
    perl -e '
        use POSIX qw(sigprocmask SIG_BLOCK SIG_UNBLOCK SIGINT SIGTERM SIGHUP SIGALRM);
        my $limit = shift;
        my $pid = 0;
        my $stop = sub {
            $SIG{$_} = "IGNORE" for qw(INT TERM HUP ALRM);
            if ($pid) { kill "TERM", -$pid; sleep 3; kill "KILL", -$pid; waitpid($pid, 0); }
            exit shift;
        };
        $SIG{ALRM} = sub { $stop->(124) };
        $SIG{INT} = sub { $stop->(130) };
        $SIG{TERM} = sub { $stop->(143) };
        $SIG{HUP} = sub { $stop->(129) };
        my $signals = POSIX::SigSet->new(SIGINT, SIGTERM, SIGHUP, SIGALRM);
        sigprocmask(SIG_BLOCK, $signals);
        $pid = fork();
        die "fork failed: $!" unless defined $pid;
        if (!$pid) {
            $SIG{$_} = "DEFAULT" for qw(INT TERM HUP ALRM);
            sigprocmask(SIG_UNBLOCK, $signals);
            setpgrp(0, 0);
            exec @ARGV;
            exit 127;
        }
        alarm $limit;
        sigprocmask(SIG_UNBLOCK, $signals);
        waitpid($pid, 0);
        my $status = $?;
        $pid = 0;
        exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
    ' "$@"
}

self_test() {
    local fails=0 got started tmp
    check() { # name wanted-status command...
        local name="$1" want="$2"
        shift 2
        "$@" >/dev/null 2>&1
        got=$?
        if [ "$got" -eq "$want" ]; then echo "ok   $name (exit $got)"; else echo "FAIL $name: wanted exit $want, got $got"; fails=$((fails + 1)); fi
    }
    check "a command that succeeds" 0 "$SELF" 5 true
    check "a command's own status is passed on" 7 "$SELF" 5 bash -c 'exit 7'
    check "a missing command is 127" 127 "$SELF" 5 /no/such/command
    check "no arguments is a usage error" 2 "$SELF"
    check "a limit that is not a number is a usage error" 2 "$SELF" soon true
    started=$SECONDS
    check "the limit kills a command that runs too long" 124 "$SELF" 1 sleep 30
    if [ $((SECONDS - started)) -lt 15 ]; then echo "ok   the limit returned in $((SECONDS - started)) s, not after the command's 30 s"
    else echo "FAIL the limit took $((SECONDS - started)) s"; fails=$((fails + 1)); fi
    tmp="$(mktemp -d)"
    # The whole process group goes: a child of the command must not survive the limit.
    "$SELF" 1 bash -c "sleep 20 & echo \$! > '$tmp/child'; wait" >/dev/null 2>&1
    sleep 1
    if kill -0 "$(cat "$tmp/child" 2>/dev/null || echo 0)" 2>/dev/null; then
        echo "FAIL a child of the command survived the limit"; fails=$((fails + 1))
        kill "$(cat "$tmp/child")" 2>/dev/null
    else
        echo "ok   a child of the command does not survive the limit"
    fi
    rm -rf "$tmp"
    if [ "$fails" -eq 0 ]; then echo "run-limited self-test: all cases passed"; return 0; fi
    echo "run-limited self-test: $fails case(s) failed" >&2
    return 1
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi
case "${1:-}" in
    '' | *[!0-9]*) echo "usage: scripts/run-limited.sh <seconds> <command> [args...] | --self-test" >&2; exit 2 ;;
esac
[ $# -ge 2 ] || { echo "usage: scripts/run-limited.sh <seconds> <command> [args...] | --self-test" >&2; exit 2; }
run_limited "$@"
