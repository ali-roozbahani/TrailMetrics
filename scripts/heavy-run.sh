#!/usr/bin/env bash
# Runs one heavy command (Gradle, xcodebuild, the KMP framework build, the gate) while holding the
# machine-wide heavy-run lock, so only one such run is going at a time, whoever starts it: a second
# caller waits until the first one is done. Two concurrent Gradle or xcodebuild runs on the 16 GB
# Mac took twice as long each and pushed swap up (the owner's measurement).
#
#   scripts/heavy-run.sh [--max-wait <seconds>] [--] <command> [<args>...]
#   scripts/heavy-run.sh --status       prints `free`, or the holder's line, and exits 0 / 3
#   scripts/heavy-run.sh --self-test
#
# The command's exit status is this script's (a signal's is 128 + its number). Other exits:
#   2   usage error or the lock file cannot be opened
#   75  --max-wait ran out while the lock was held by another run (default: wait without limit)
#   127 the command could not be started
#
# What counts as heavy: ./gradlew (any task), xcodebuild, scripts/build-kmp-framework.sh and
# scripts/pre-push-check.sh (which starts itself under this script, so a bare run of the gate is
# covered). A subagent in a worktree runs its module's tests the same way:
# `scripts/heavy-run.sh ./gradlew :<module>:testDebugUnitTest`.
#
# How the lock works. A small perl process holds an exclusive flock(2) on
# ${TM_LOCK_DIR:-$HOME/agent-workspace/queue/locks}/heavy-run.lock for as long as the command runs;
# the command is its child and does not inherit the lock's file descriptor. The kernel drops the lock
# when the holder exits for any reason, so there is no stale lock to clean up and nothing to time
# out: a holder killed with SIGKILL frees it at once (its command, if still running, is then no
# longer counted). Gradle daemons started by the command do not keep the lock either. The info file
# next to the lock (holder pid, start time, directory, command) is for the waiting callers' message
# only; the lock is the flock, never that file. A waiter prints who it waits for at once and every
# 60 seconds.
#
# Re-entry: the command runs with TM_HEAVY_RUN_HELD=<holder pid>. A heavy command that starts
# another one (the gate runs Gradle and xcodebuild; Xcode's build phase runs Gradle) calls this
# script again; it sees the variable and a live holder pid and runs the command directly instead of
# waiting for itself.
#
# Limits: a guardrail for agents and scripts that follow it, not a wall: a Gradle or xcodebuild
# started from a terminal without this script is not counted. flock is per machine (a lock file on a
# network disk is not supported). Needs perl (macOS and Linux have it). Bash 3.2 compatible.
set -u

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
LOCK_DIR="${TM_LOCK_DIR:-$HOME/agent-workspace/queue/locks}"
LOCK="$LOCK_DIR/heavy-run.lock"
INFO="$LOCK_DIR/heavy-run.info"
USAGE="usage: scripts/heavy-run.sh [--max-wait <seconds>] [--] <command> [<args>...]
       scripts/heavy-run.sh --status | --self-test"

usage() { echo "$USAGE" >&2; exit 2; }

# The holder. Arguments: lock file, info file, max wait (-1 = none), then the command.
# With the max wait "status": try the lock once, report, exit 0 (free) or 3 (held).
PERL_HOLDER='
use strict; use warnings; no warnings "exec";
use Fcntl qw(:flock);
use POSIX qw(strftime);
my ($lock, $info, $maxwait, @cmd) = @ARGV;
$| = 1;
open(my $fh, ">>", $lock) or do { print STDERR "heavy-run: cannot open $lock: $!\n"; exit 2 };
sub holder_line {
    open(my $in, "<", $info) or return "another heavy run (no details)";
    my $l = <$in>; close $in;
    return "another heavy run (no details)" unless defined $l;
    chomp $l;
    my ($pid, $since, $cwd, $c) = split(/\t/, $l, 4);
    return sprintf("pid %s since %s in %s: %s", $pid // "?", $since // "?", $cwd // "?", $c // "?");
}
if ($maxwait eq "status") {
    if (flock($fh, LOCK_EX | LOCK_NB)) { print "free\n"; exit 0 }
    print "held by ", holder_line(), "\n";
    exit 3;
}
my $start = time;
my $last = 0;
until (flock($fh, LOCK_EX | LOCK_NB)) {
    my $now = time;
    if ($maxwait >= 0 && $now - $start >= $maxwait) {
        print STDERR "heavy-run: gave up after ${maxwait}s, held by ", holder_line(), "\n";
        exit 75;
    }
    if ($now - $last >= 60) {
        print STDERR "heavy-run: waiting for ", holder_line(), "\n";
        $last = $now;
    }
    select(undef, undef, undef, 1);
}
if (open(my $out, ">", $info)) {
    my $cwd = $ENV{PWD} // "?";
    my $c = join(" ", @cmd); $c =~ s/[\t\r\n]+/ /g;
    print $out join("\t", $$, strftime("%Y-%m-%dT%H:%M:%S", localtime), $cwd, $c), "\n";
    close $out;
}
$ENV{TM_HEAVY_RUN_HELD} = $$;
my $pid = fork();
die "heavy-run: fork failed: $!\n" unless defined $pid;
if (!$pid) {
    exec { $cmd[0] } @cmd;
    print STDERR "heavy-run: cannot run $cmd[0]: $!\n";
    exit 127;
}
for my $sig (qw(INT TERM HUP QUIT)) { $SIG{$sig} = sub { kill $_[0], $pid } }
my $r;
do { $r = waitpid($pid, 0) } while ($r == -1 && $!{EINTR});
my $st = $?;
unlink $info;
exit(($st & 127) ? 128 + ($st & 127) : $st >> 8);
'

holder() { # holder <max wait|status> [command...]
    mkdir -p "$LOCK_DIR" || { echo "heavy-run: cannot create $LOCK_DIR" >&2; exit 2; }
    exec perl -e "$PERL_HOLDER" "$LOCK" "$INFO" "$@"
}

run() {
    local maxwait=-1
    while [ $# -gt 0 ]; do
        case "$1" in
            --max-wait)
                [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || usage
                maxwait="$2"; shift 2 ;;
            --) shift; break ;;
            -*) usage ;;
            *) break ;;
        esac
    done
    [ $# -ge 1 ] || usage
    if [ -n "${TM_HEAVY_RUN_HELD:-}" ] && [[ "$TM_HEAVY_RUN_HELD" =~ ^[0-9]+$ ]] && kill -0 "$TM_HEAVY_RUN_HELD" 2>/dev/null; then
        exec "$@"
    fi
    holder "$maxwait" "$@"
}

self_test() {
    local tmp fails=0 out rc i
    tmp="$(mktemp -d)"
    TMP_ROOT="$tmp"
    trap 'rm -rf -- "$TMP_ROOT"' EXIT
    export TM_LOCK_DIR="$tmp/locks"
    unset TM_HEAVY_RUN_HELD
    ok() { echo "ok   $1"; }
    bad() { echo "FAIL $1" >&2; shift; [ $# -eq 0 ] || printf '%s\n' "$@" | sed 's/^/       /' >&2; fails=$((fails + 1)); }
    expect_rc() { # expect_rc <description> <exit> <command...>
        local d="$1" want="$2"; shift 2
        out="$("$@" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$want" ]; then ok "$d"; else bad "$d: expected exit $want, got $rc" "$out"; fi
    }
    wait_for_file() { # wait_for_file <path>: up to 10 s
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            [ -e "$1" ] && return 0
            sleep 0.5
        done
        return 1
    }

    expect_rc "passes the command's exit status through" 7 bash "$SELF" bash -c 'exit 7'
    expect_rc "exit 0 for a command that succeeds" 0 bash "$SELF" -- true
    expect_rc "127 for a command that does not exist" 127 bash "$SELF" /nonexistent/heavy-run-test-command
    expect_rc "usage error without a command" 2 bash "$SELF"
    expect_rc "usage error for --max-wait without a number" 2 bash "$SELF" --max-wait x true
    expect_rc "a signal's status is 128 plus its number" 143 bash "$SELF" bash -c 'kill -TERM $$'
    out="$(bash "$SELF" --status)"; rc=$?
    if [ "$rc" = 0 ] && [ "$out" = free ]; then ok "status says free when nothing runs"; else bad "status free: exit $rc" "$out"; fi

    # Two callers: the second one starts only after the first one has finished.
    local log="$tmp/log"
    : > "$log"
    bash "$SELF" bash -c "echo A-start >> '$log'; sleep 2; echo A-end >> '$log'" &
    local a=$!
    if wait_for_file "$tmp/locks/heavy-run.info"; then
        out="$(bash "$SELF" --status)"; rc=$?
        if [ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'held by pid .*A-start'; then ok "status names the holder while a run is going"; else bad "status held: exit $rc" "$out"; fi
        expect_rc "--max-wait gives up with 75 while the lock is held" 75 bash "$SELF" --max-wait 1 true
        bash "$SELF" bash -c "echo B-start >> '$log'"
        wait "$a"
        if [ "$(tr '\n' ' ' < "$log")" = "A-start A-end B-start " ]; then ok "a second caller waits for the first"; else bad "order of the two runs" "$(cat "$log")"; fi
    else
        bad "the first run never started"; wait "$a"
    fi

    # Re-entry: a heavy command that starts another heavy command does not wait for itself.
    expect_rc "a nested call runs at once" 0 bash "$SELF" bash -c "\"$SELF\" --max-wait 3 true"

    # A holder killed with SIGKILL frees the lock; its orphaned command does not keep it.
    rm -f "$tmp/childpid" "$tmp/locks/heavy-run.info"
    bash "$SELF" bash -c "echo \$\$ > '$tmp/childpid'; exec sleep 30" &
    local b=$!
    if wait_for_file "$tmp/childpid" && wait_for_file "$tmp/locks/heavy-run.info"; then
        local holder_pid
        holder_pid="$(cut -f1 "$tmp/locks/heavy-run.info")"
        kill -9 "$holder_pid" 2>/dev/null
        wait "$b" 2>/dev/null
        expect_rc "the lock is free after the holder was killed" 0 bash "$SELF" --max-wait 5 true
        kill "$(cat "$tmp/childpid")" 2>/dev/null
    else
        bad "the run to kill never started"; kill "$b" 2>/dev/null
    fi

    if [ "$fails" -eq 0 ]; then echo "heavy-run self-test: all passed"; return 0; fi
    echo "heavy-run self-test: $fails failed" >&2
    return 1
}

case "${1:-}" in
    --self-test) [ $# -eq 1 ] || usage; self_test; exit $? ;;
    --status) [ $# -eq 1 ] || usage; holder status ;;
    "") usage ;;
    *) run "$@" ;;
esac
