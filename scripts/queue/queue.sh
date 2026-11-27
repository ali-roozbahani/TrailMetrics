#!/usr/bin/env bash
# The local, serial PR queue: which follow-up PR to build, push or wait for next. At most one PR of
# the queue is pushed (in CI) at a time; the others are built locally meanwhile, a dependent entry
# on its parent's local branch, and pushed against `main` only after its parent is merged. Entries
# that need the owner (kind `owner`: a protected path, ESCALATE_TO_HUMAN) come last.
#
#   scripts/queue/queue.sh add <slug> --branch <branch> --task <file|-> [--after <slug>] [--kind agent|owner]
#   scripts/queue/queue.sh task <slug>
#   scripts/queue/queue.sh set <slug> <field>=<value>...     fields: status, pr, branch
#   scripts/queue/queue.sh show
#   scripts/queue/queue.sh next
#   scripts/queue/queue.sh may-push <branch>
#   scripts/queue/queue.sh --self-test
#
# The queue file: ${QUEUE_FILE:-$HOME/agent-workspace/queue/queue.tsv}, outside the repository
# (scripts/dev/clean-agent-workspace.sh keeps this file and the `queue/` folder, and cleans inside the
# folder only what its header lists). One tab-separated line per
# entry, lines starting with `#` ignored:
#   order  slug  branch  after  kind  status  pr
#   order   integer given by `add` (insertion order)    after   a slug, or `-`
#   kind    agent | owner                                status  planned | building | ready | pushed | merged | dropped
#   pr      the PR number, or `-`
# An entry is open while its status is not `merged` or `dropped`. Queue order: agent entries before
# owner entries, then by `order`. There is no limit on open entries (owner decision of 2026-11-27): a
# new entry gets the next `order`, so it comes after every entry of its kind.
#
# The task text. Every entry carries the text of its task, so a session that did not queue it can build
# it: `add` needs `--task <file>` (or `--task -` for stdin) and copies the text to `tasks/<slug>.md` in
# the folder of the queue file; `task <slug>` prints it. The cleaner deletes a text only once its entry is
# `merged` or `dropped` and the text is older than 3 days, never the text of an open entry. The text
# is what the task template (`task-template.md`) asks for: what to do, its scope, when it is done.
#
# add refuses: no task text (no --task, a file that is not there, an empty or blank text), a slug
#   already in the file, an --after slug that is not in the file or is dropped, an agent entry after an owner entry, a branch already in the file, a branch
#   without a feature/, bugfix/ or chore/ prefix. A new entry is `planned` with PR `-`.
# set refuses: an unknown slug, field or status, a PR that is not a number or `-`; status `pushed`
#   without a PR number, for an entry that is not `ready`, while another entry is pushed, for an
#   entry that is not the first open one in queue order, or whose parent is not merged; status
#   `merged` without a PR number, or for an entry that is not `pushed`, and status `dropped` for an entry
#   that an open entry comes after (it would hold that entry; `set <slug> --force status=dropped` overrides).
#
# next prints exactly one line, from the file alone (no network, no git):
#   PUSH <slug>                   nothing is pushed, the first open entry is `ready`, its parent (if
#                                 any) is merged: gate, local review, push, PR against main
#   FINISH_BUILD <slug>           an entry is `building` (it is finished before another starts)
#   BUILD <slug>                  the first `planned` entry whose parent is ready, pushed or merged
#                                 (or that has none); a dependent one is built on the parent's branch
#   WAIT <slug> #<pr> <kind>      an entry is pushed and nothing is left to build
#   HOLD <slug> after <parent>    nothing is pushed and the first open entry cannot go on because
#                                 its parent is dropped: re-point or drop it
#   DONE                          no open entry
# While nothing is pushed, a first open entry that is not ready is built (FINISH_BUILD, BUILD) before
# anything else; while an entry is pushed, the other entries are built in queue order.
#
# add and set end with a line `next: <what next would print>`, so the agent reads its next action
# from the script, not from its own plan: after `add` of the first entry it says BUILD, after `set
# <slug> status=ready` it says PUSH, and a second entry is built only while the first is pushed.
#
# set also runs the workspace cleaner (scripts/dev/clean-agent-workspace.sh) when an entry becomes `merged`
# or `dropped`, and prints its summary line before the `next:` line: the workspace is cleaned as a long
# queue session goes. The cleaner keeps everything an open entry uses and refuses a directory that is not
# the agent workspace, so it does nothing for a queue file outside it; its failure never fails the `set`.
#
# may-push <branch> says whether a push of <branch> (or a PR from it) is allowed, from the file alone
# (owner decision of 2026-11-26: a PR of the queue is pushed only when the queue says PUSH for it). The
# push hook (scripts/claude-hooks/require-local-review.sh) asks it for every branch a `git push` or
# `gh pr create` names; a `refs/heads/` prefix is ignored. One line:
#   OUTSIDE <branch>        exit 0   no entry has this branch (a task outside the queue, an epic branch)
#   ALLOW <slug> PUSH       exit 0   `next` prints `PUSH <slug>`: the entry's first push and its PR
#   ALLOW <slug> pushed #N  exit 0   the entry is pushed: a new commit for its open PR (a CI fix, a merge)
#   REFUSE <slug> ...       exit 1   any other state: planned, building, ready behind another entry,
#                                    merged or dropped
# A missing queue file is OUTSIDE for every branch; an unreadable one exits 2 (the hook then blocks).
#
# show prints the entries in queue order as aligned columns (awk only, no `column`).
#
# Lock: `add` and `set` read the file, validate against it and replace it, so two of them at the same
# time would lose one update (and could both take the same `order`). Each runs under an exclusive
# flock(2) on `<queue file>.lock`, held from before the read until the process ends; a second one
# waits, and refuses (exit 1, "the queue file is locked by another add or set") after
# ${TM_QUEUE_LOCK_WAIT:-30} seconds. The kernel drops the lock when its holder dies, so a killed `add`
# leaves nothing to clean up. `show` and `next` take no lock: the file is replaced atomically, so they
# read either the old or the new state. The lock is per machine, like the file. Needs perl.
#
# Exit: 0 ok, 1 refused (reason on stderr), 2 usage error or unreadable queue file.
# Bash 3.2 compatible.
set -u -o pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
QUEUE_FILE="${QUEUE_FILE:-$HOME/agent-workspace/queue/queue.tsv}"
TAB="$(printf '\t')"
USAGE="usage: scripts/queue/queue.sh add <slug> --branch <branch> --task <file|-> [--after <slug>] [--kind agent|owner]
       scripts/queue/queue.sh task <slug>
       scripts/queue/queue.sh set <slug> <field>=<value>...   (status, pr, branch)
       scripts/queue/queue.sh may-push <branch>
       scripts/queue/queue.sh show | next | --self-test"

usage() { echo "$USAGE" >&2; exit 2; }
refuse() { echo "queue: refused: $*" >&2; exit 1; }
die() { echo "queue: $*" >&2; exit 2; }

# entries: the valid entry lines of the queue file (no comments, no blank lines); exits 2 on a bad line.
entries() {
    [ -f "$QUEUE_FILE" ] || return 0
    awk -F '\t' -v f="$QUEUE_FILE" '
        /^#/ || /^[[:space:]]*$/ { next }
        NF != 7 || $1 !~ /^[0-9]+$/ || $5 !~ /^(agent|owner)$/ ||
        $6 !~ /^(planned|building|ready|pushed|merged|dropped)$/ || $7 !~ /^([0-9]+|-)$/ {
            printf "queue: %s:%d is not <order> <slug> <branch> <after> <kind> <status> <pr>\n", f, NR > "/dev/stderr"; bad = 1; exit 2
        }
        { print }
        END { if (bad) exit 2 }' "$QUEUE_FILE" || exit 2
}

# sorted: the entries in queue order (agent first, then order).
sorted() {
    entries | awk -F '\t' '{ print ($5 == "agent" ? 0 : 1) "\t" $0 }' | sort -t "$TAB" -k1,1n -k2,2n | cut -f2-
}

field() { # field <slug> <column number>
    entries | awk -F '\t' -v s="$1" -v c="$2" '$2 == s { print $c; exit }'
}

is_open() { case "$1" in merged | dropped) return 1 ;; *) return 0 ;; esac; }

LOCK_WAIT="${TM_QUEUE_LOCK_WAIT:-30}"
# Holds <queue file>.lock (flock) and then execs `bash <this script> <args>`; the descriptor stays open
# across the exec ($^F), so the lock lives exactly as long as that process.
PERL_LOCK='
use strict; use warnings; no warnings "exec";
use Fcntl qw(:flock);
my ($lock, $wait, $qf, @cmd) = @ARGV;
$^F = 255;
open(my $fh, ">>", $lock) or do { print STDERR "queue: cannot open $lock: $!\n"; exit 2 };
my $deadline = time + $wait;
until (flock($fh, LOCK_EX | LOCK_NB)) {
    if (time >= $deadline) {
        print STDERR "queue: refused: the queue file is locked by another add or set (waited $wait s); run it again\n";
        exit 1;
    }
    select(undef, undef, undef, 0.1);
}
$ENV{TM_QUEUE_LOCKED} = $qf;
exec { $cmd[0] } @cmd;
print STDERR "queue: cannot run $cmd[0]: $!\n";
exit 127;
'

# locked <add|set> <args>...: runs cmd_<sub> holding the queue file's lock (see the header, "Lock").
locked() {
    local sub="$1"
    shift
    if [ "${TM_QUEUE_LOCKED:-}" = "$QUEUE_FILE" ]; then "cmd_$sub" "$@"; return; fi
    mkdir -p "$(dirname "$QUEUE_FILE")" || die "cannot create $(dirname "$QUEUE_FILE")"
    exec perl -e "$PERL_LOCK" "$QUEUE_FILE.lock" "$LOCK_WAIT" "$QUEUE_FILE" bash "$SELF" "$sub" "$@"
}

write_file() { # write_file <content file>: atomic replace
    local dir
    dir="$(dirname "$QUEUE_FILE")"
    mkdir -p "$dir" || die "cannot create $dir"
    cp -- "$1" "$QUEUE_FILE.tmp.$$" && mv -- "$QUEUE_FILE.tmp.$$" "$QUEUE_FILE" || die "cannot write $QUEUE_FILE"
}

# task_file <slug>: where the task text of an entry is kept.
task_file() { echo "$(dirname "$QUEUE_FILE")/tasks/$1.md"; }

cmd_add() {
    local slug="${1:-}" branch="" after="-" kind="agent" task="" text n open order pkind pstatus tmp
    [ -n "$slug" ] || usage
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --branch) [ "$#" -ge 2 ] || usage; branch="$2"; shift 2 ;;
            --after) [ "$#" -ge 2 ] || usage; after="$2"; shift 2 ;;
            --kind) [ "$#" -ge 2 ] || usage; kind="$2"; shift 2 ;;
            --task) [ "$#" -ge 2 ] || usage; task="$2"; shift 2 ;;
            *) usage ;;
        esac
    done
    [ -n "$branch" ] || usage
    [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || refuse "slug '$slug' is not kebab-case"
    [[ "$branch" =~ ^(feature|bugfix|chore)/[A-Za-z0-9._/-]+$ ]] || refuse "branch '$branch' has no feature/, bugfix/ or chore/ prefix"
    case "$kind" in agent | owner) ;; *) refuse "kind '$kind' is not agent or owner" ;; esac
    [ -n "$task" ] || refuse "an entry needs its task text: --task <file> (or --task - for stdin)"
    if [ "$task" = - ]; then text="$(cat)"; else
        [ -f "$task" ] || refuse "the task text file '$task' does not exist"
        text="$(cat -- "$task")" || refuse "cannot read the task text file '$task'"
    fi
    [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || refuse "the task text is empty"
    entries > /dev/null
    [ -z "$(field "$slug" 2)" ] || refuse "slug '$slug' is already in the queue"
    n="$(entries | awk -F '\t' -v b="$branch" '$3 == b' | wc -l | tr -d ' ')"
    [ "$n" = 0 ] || refuse "branch '$branch' is already in the queue"
    if [ "$after" != "-" ]; then
        [ "$after" != "$slug" ] || refuse "an entry cannot come after itself"
        pkind="$(field "$after" 5)"
        [ -n "$pkind" ] || refuse "--after '$after' is not in the queue"
        pstatus="$(field "$after" 6)"
        [ "$pstatus" != dropped ] || refuse "--after '$after' is dropped"
        if [ "$kind" = agent ] && [ "$pkind" = owner ]; then
            refuse "an agent entry cannot come after the owner entry '$after' (owner entries are pushed last)"
        fi
    fi
    order="$(entries | awk -F '\t' 'BEGIN { m = 0 } $1 > m { m = $1 } END { print m + 1 }')"
    # The text first, so an entry in the file always has its text; written whole, then moved into place.
    mkdir -p "$(dirname "$(task_file "$slug")")" || die "cannot create $(dirname "$(task_file "$slug")")"
    tmp="$(mktemp)"
    printf '%s\n' "$text" > "$tmp" && cp -- "$tmp" "$(task_file "$slug").tmp.$$" && mv -- "$(task_file "$slug").tmp.$$" "$(task_file "$slug")" || die "cannot write $(task_file "$slug")"
    rm -f -- "$tmp"
    tmp="$(mktemp)"
    { [ -f "$QUEUE_FILE" ] && cat -- "$QUEUE_FILE"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$order" "$slug" "$branch" "$after" "$kind" planned -; } > "$tmp"
    write_file "$tmp"
    rm -f -- "$tmp"
    if [ "$after" = - ]; then echo "added $slug ($kind, order $order)"; else echo "added $slug ($kind, order $order, after $after)"; fi
    print_next
}

cmd_task() {
    local slug="${1:-}"
    [ -n "$slug" ] || usage
    entries > /dev/null
    [ -n "$(field "$slug" 2)" ] || refuse "'$slug' is not in the queue"
    [ -f "$(task_file "$slug")" ] || refuse "'$slug' has no task text ($(task_file "$slug") is missing)"
    cat -- "$(task_file "$slug")"
}

# clean_workspace: runs scripts/dev/clean-agent-workspace.sh on the workspace the queue file lives in
# (<workspace>/queue/queue.tsv), best effort, so a long queue session cleans the workspace as entries
# finish and not only at the start of a task. The cleaner never deletes what an open entry uses, and
# refuses a directory that is not the agent workspace (a test's temporary queue), so this is safe to
# run here; its failure never fails the `set`, but it is not silent: a cleaner that exits with a status
# other than 0 (done) or 2 (the guard refused a directory that is not the agent workspace) leaves a
# one-line warning on stderr, with the cleaner's own first error line. It prints the cleaner's summary line.
clean_workspace() {
    local cleaner all rc=0 summary problem
    cleaner="$(dirname "$SELF")/../dev/clean-agent-workspace.sh"
    [ -f "$cleaner" ] || return 0
    all="$(bash "$cleaner" "$(dirname "$(dirname "$QUEUE_FILE")")" 2>&1)" || rc=$?
    summary="$(printf '%s\n' "$all" | grep -E '^clean-agent-workspace: (removed|would remove) ' | tail -n 1)"
    [ -z "$summary" ] || echo "$summary"
    if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then
        problem="$(printf '%s\n' "$all" | grep -E '^clean-agent-workspace: could not' | head -n 1)"
        echo "queue: warning: the workspace cleaner exited with status $rc${problem:+ ($problem)}; run scripts/dev/clean-agent-workspace.sh to see it" >&2
    fi
}

# print_next: the line `next` would print, after the change just made.
print_next() { echo "next: $(cmd_next)"; }

cmd_set() {
    local slug="${1:-}" kv key val status pr branch tmp first other parent old force=0
    [ -n "$slug" ] && [ "$#" -ge 2 ] || usage
    shift
    entries > /dev/null
    [ -n "$(field "$slug" 2)" ] || refuse "'$slug' is not in the queue"
    status="$(field "$slug" 6)"; old="$status"; pr="$(field "$slug" 7)"; branch="$(field "$slug" 3)"
    for kv in "$@"; do
        if [ "$kv" = --force ]; then force=1; continue; fi
        key="${kv%%=*}"; val="${kv#*=}"
        [ "$key" != "$kv" ] || usage
        case "$key" in
            status)
                case "$val" in planned | building | ready | pushed | merged | dropped) status="$val" ;;
                    *) refuse "status '$val' is not planned, building, ready, pushed, merged or dropped" ;; esac ;;
            pr) [[ "$val" =~ ^([0-9]+|-)$ ]] || refuse "pr '$val' is not a number or -"; pr="$val" ;;
            branch)
                [[ "$val" =~ ^(feature|bugfix|chore)/[A-Za-z0-9._/-]+$ ]] || refuse "branch '$val' has no feature/, bugfix/ or chore/ prefix"
                other="$(entries | awk -F '\t' -v b="$val" -v s="$slug" '$3 == b && $2 != s { print $2; exit }')"
                [ -z "$other" ] || refuse "branch '$val' belongs to '$other'"
                branch="$val" ;;
            *) refuse "unknown field '$key' (status, pr, branch)" ;;
        esac
    done
    if [ "$status" = dropped ] && [ "$old" != dropped ] && [ "$force" != 1 ]; then
        other="$(entries | awk -F '\t' -v s="$slug" '$4 == s && $6 != "merged" && $6 != "dropped" { print $2; exit }')"
        [ -z "$other" ] || refuse "'$other' comes after '$slug' and is open; dropping '$slug' would hold it (merged is the status of a merged PR; or add --force)"
    fi
    if [ "$status" = pushed ] && [ "$old" != pushed ]; then
        [ "$pr" != - ] || refuse "status pushed needs pr=<number>"
        [ "$old" = ready ] || refuse "'$slug' is $old; only a ready entry is pushed"
        other="$(entries | awk -F '\t' -v s="$slug" '$6 == "pushed" && $2 != s { print $2; exit }')"
        [ -z "$other" ] || refuse "'$other' is pushed; one PR of the queue is pushed at a time"
        first="$(sorted | awk -F '\t' '$6 != "merged" && $6 != "dropped" { print $2; exit }')"
        [ "$first" = "$slug" ] || refuse "'$first' comes first in the queue; '$slug' is pushed after it is merged"
        parent="$(field "$slug" 4)"
        if [ "$parent" != - ] && [ "$(field "$parent" 6)" != merged ]; then
            refuse "the parent '$parent' is not merged"
        fi
    fi
    if [ "$status" = merged ] && [ "$pr" = - ]; then refuse "status merged needs pr=<number>"; fi
    if [ "$status" = merged ] && [ "$old" != merged ] && [ "$old" != pushed ]; then
        refuse "'$slug' is $old; only a pushed entry is merged"
    fi
    tmp="$(mktemp)"
    awk -F '\t' -v OFS='\t' -v s="$slug" -v st="$status" -v p="$pr" -v b="$branch" '
        !/^#/ && NF == 7 && $2 == s { $3 = b; $6 = st; $7 = p } { print }' "$QUEUE_FILE" > "$tmp"
    write_file "$tmp"
    rm -f -- "$tmp"
    echo "set $slug: status $status, pr $pr, branch $branch"
    case "$status" in merged | dropped) [ "$old" = "$status" ] || clean_workspace ;; esac
    print_next
}

cmd_show() {
    local rows
    rows="$(sorted)" || exit 2
    if [ -z "$rows" ]; then echo "(queue empty: $QUEUE_FILE)"; return 0; fi
    { printf 'order\tslug\tbranch\tafter\tkind\tstatus\tpr\n'; printf '%s\n' "$rows"; } | awk -F '\t' '
        { n[NR] = NF; for (i = 1; i <= NF; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } }
        END {
            for (r = 1; r <= NR; r++) {
                line = ""
                for (i = 1; i < n[r]; i++) line = line sprintf("%-" (w[i] + 2) "s", c[r, i])
                print line c[r, n[r]]
            }
        }'
}

# may-push <branch>: whether a push of <branch>, or a PR from it, is allowed by the queue (see the header).
cmd_may_push() {
    local branch="${1#refs/heads/}" row slug status pr nxt
    [ -n "$branch" ] || usage
    row="$(entries | awk -F '\t' -v b="$branch" '$3 == b { print; exit }')" || exit 2
    if [ -z "$row" ]; then echo "OUTSIDE $branch"; return 0; fi
    slug="$(printf '%s\n' "$row" | cut -f2)"; status="$(printf '%s\n' "$row" | cut -f6)"; pr="$(printf '%s\n' "$row" | cut -f7)"
    if [ "$status" = pushed ]; then echo "ALLOW $slug pushed #$pr"; return 0; fi
    nxt="$(cmd_next)" || exit 2
    if [ "$nxt" = "PUSH $slug" ]; then echo "ALLOW $slug PUSH"; return 0; fi
    echo "REFUSE $slug is $status and the queue says '$nxt', not 'PUSH $slug'"
    return 1
}

cmd_next() {
    local rows
    rows="$(sorted)" || exit 2
    printf '%s\n' "$rows" | awk -F '\t' '
        NF != 7 { next }
        { n++; slug[n] = $2; after[n] = $4; kind[n] = $5; st[n] = $6; pr[n] = $7; status[$2] = $6 }
        function open(i) { return st[i] != "merged" && st[i] != "dropped" }
        function parent_ok(i, want,   p) {   # want: "merged" or "built"
            if (after[i] == "-") return 1
            p = status[after[i]]
            if (want == "merged") return p == "merged"
            return p == "ready" || p == "pushed" || p == "merged"
        }
        function build(   i) {
            for (i = 1; i <= n; i++) if (st[i] == "building") { print "FINISH_BUILD " slug[i]; return 1 }
            for (i = 1; i <= n; i++) if (st[i] == "planned" && parent_ok(i, "built")) { print "BUILD " slug[i]; return 1 }
            return 0
        }
        END {
            for (i = 1; i <= n; i++) if (st[i] == "pushed") { pushed = i; break }
            if (pushed) {
                if (build()) exit 0
                print "WAIT " slug[pushed] " #" pr[pushed] " " kind[pushed]; exit 0
            }
            for (i = 1; i <= n; i++) if (open(i)) { first = i; break }
            if (!first) { print "DONE"; exit 0 }
            # A parent always sorts ahead of its child, so the first open entry has a parent that is
            # merged, or dropped (or missing from a hand-edited file): the entry cannot go on.
            if (!parent_ok(first, "merged")) { print "HOLD " slug[first] " after " after[first]; exit 0 }
            if (st[first] == "ready") { print "PUSH " slug[first]; exit 0 }
            if (st[first] == "building") { print "FINISH_BUILD " slug[first]; exit 0 }
            print "BUILD " slug[first]
        }'
}

self_test() {
    local tmp fails=0 out rc
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    # has_line <line> <text>: the text has a line equal to <line>, whole (`BUILD a` is not `FINISH_BUILD a`).
    has_line() { printf '%s\n' "$2" | grep -qxF -- "$1"; }
    check() { # check <description> <expected line, whole> <expected exit> <command...>
        local d="$1" want="$2" wantrc="$3"
        shift 3
        out="$("$@" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$wantrc" ] && has_line "$want" "$out"; then
            echo "ok   $d"
        else
            echo "FAIL $d: expected exit $wantrc and '$want', got exit $rc:" >&2
            printf '%s\n' "$out" | sed 's/^/       /' >&2
            fails=$((fails + 1))
        fi
    }
    # The comparison itself: a substring of a line is not a match.
    if has_line "BUILD a" "FINISH_BUILD a" || ! has_line "BUILD a" "$(printf 'x\nBUILD a')"; then
        echo "FAIL the comparison is not whole-line" >&2; fails=$((fails + 1))
    else
        echo "ok   the comparison is whole-line (BUILD a does not match FINISH_BUILD a)"
    fi
    printf 'Do the thing.\nScope: this file.\n' > "$tmp/task.txt"
    # An add without its own --task gets the common text file, so the cases below stay about their subject.
    q() {
        case " $* " in
            " add "*" --task "*) QUEUE_FILE="$QF" bash "$SELF" "$@" ;;
            " add "*) QUEUE_FILE="$QF" bash "$SELF" "$@" --task "$tmp/task.txt" ;;
            *) QUEUE_FILE="$QF" bash "$SELF" "$@" ;;
        esac
    }
    fresh() { QF="$tmp/$1/queue.tsv"; }
    # line <order> <slug> <after> <kind> <status> <pr>: one entry, written straight into the file
    line() { mkdir -p "$(dirname "$QF")"; printf '%s\t%s\tchore/%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$2" "$3" "$4" "$5" "$6" >> "$QF"; }

    q_fresh_add() { QF="$tmp/nx1/queue.tsv"; q add a --branch chore/a; }
    q_ready_first() { QF="$tmp/nx2/queue.tsv"; q add a --branch chore/a >/dev/null && q add b --branch chore/b >/dev/null \
        && q set a status=building >/dev/null && q set a status=ready; }
    q_two_entries() { QF="$tmp/nx3/queue.tsv"; q add a --branch chore/a >/dev/null && q add b --branch chore/b >/dev/null \
        && q set a status=building; }

    # add, ordering, refusals
    fresh add
    check "next on a missing file" "DONE" 0 q next
    check "add a" "added a (agent, order 1)" 0 q add a --branch chore/a
    check "add writes the queue file" "$QF" 0 sh -c "test -f '$QF' && echo '$QF'"
    check "add owner o" "added o (owner, order 2)" 0 q add o --branch chore/o --kind owner
    check "add b after a" "added b (agent, order 3, after a)" 0 q add b --branch chore/b --after a
    check "duplicate slug" "queue: refused: slug 'a' is already in the queue" 1 q add a --branch chore/a2
    check "duplicate branch" "queue: refused: branch 'chore/a' is already in the queue" 1 q add c --branch chore/a
    check "unknown --after" "queue: refused: --after 'zz' is not in the queue" 1 q add c --branch chore/c --after zz
    check "agent after owner" "queue: refused: an agent entry cannot come after the owner entry 'o' (owner entries are pushed last)" 1 q add c --branch chore/c --after o
    check "owner after owner is fine" "added o2 (owner, order 4, after o)" 0 q add o2 --branch chore/o2 --kind owner --after o
    check "bad branch prefix" "queue: refused: branch 'docs/c' has no feature/, bugfix/ or chore/ prefix" 1 q add c --branch docs/c
    check "bad kind" "queue: refused: kind 'human' is not agent or owner" 1 q add c --branch chore/c --kind human
    check "bad slug" "queue: refused: slug 'C_1' is not kebab-case" 1 q add C_1 --branch chore/c
    check "fifth open entry" "added c (agent, order 5)" 0 q add c --branch chore/c
    check "agent entries order before owner entries" "5      c     chore/c   -      agent  planned  -" 0 sh -c "QUEUE_FILE='$QF' bash '$SELF' show | sed -n 4p"
    check "owner entries last" "4      o2    chore/o2  o      owner  planned  -" 0 sh -c "QUEUE_FILE='$QF' bash '$SELF' show | tail -1"
    check "next builds the first entry" "BUILD a" 0 q next
    check "set unknown slug" "queue: refused: 'zz' is not in the queue" 1 q set zz status=ready
    check "set bad status" "queue: refused: status 'done' is not planned, building, ready, pushed, merged or dropped" 1 q set a status=done
    check "set bad pr" "queue: refused: pr 'x1' is not a number or -" 1 q set a pr=x1
    check "set bad field" "queue: refused: unknown field 'kind' (status, pr, branch)" 1 q set a kind=owner
    check "pushed needs a PR" "queue: refused: status pushed needs pr=<number>" 1 q set a status=pushed
    check "a planned entry is not pushed" "queue: refused: 'c' is planned; only a ready entry is pushed" 1 q set c status=pushed pr=9
    check "merged needs a PR" "queue: refused: status merged needs pr=<number>" 1 q set c status=merged
    check "a planned entry is not merged" "queue: refused: 'c' is planned; only a pushed entry is merged" 1 q set c status=merged pr=9
    check "set a building" "set a: status building, pr -, branch chore/a" 0 q set a status=building
    check "FINISH_BUILD the building entry" "FINISH_BUILD a" 0 q next
    check "set a ready" "set a: status ready, pr -, branch chore/a" 0 q set a status=ready
    check "PUSH a ready first entry" "PUSH a" 0 q next
    check "set a pushed" "set a: status pushed, pr 11, branch chore/a" 0 q set a status=pushed pr=11
    check "child of a pushed parent is built" "BUILD b" 0 q next
    check "b ready" "set b: status ready, pr -, branch chore/b" 0 q set b status=ready
    check "a ready entry is not merged" "queue: refused: 'b' is ready; only a pushed entry is merged" 1 q set b status=merged pr=12
    check "next independent entry is built" "BUILD c" 0 q next
    check "a child is not pushed while its parent is pushed" "queue: refused: 'a' is pushed; one PR of the queue is pushed at a time" 1 q set b status=pushed pr=12
    check "set c dropped" "set c: status dropped, pr -, branch chore/c" 0 q set c status=dropped
    check "add after a dropped entry refused" "queue: refused: --after 'c' is dropped" 1 q add d --branch chore/d --after c
    check "add d" "added d (agent, order 6)" 0 q add d --branch chore/d
    check "a sixth open entry is added (no limit)" "added e (agent, order 7)" 0 q add e --branch chore/e
    check "a seventh open entry is added" "added f (agent, order 8)" 0 q add f --branch chore/f
    check "a new agent entry comes after the open agent entries, before the owner entries" "8      f     chore/f   -      agent  planned  -" 0 sh -c "QUEUE_FILE='$QF' bash '$SELF' show | sed -n 7p"
    check "the owner entries stay last after it" "4      o2    chore/o2  o      owner  planned  -" 0 sh -c "QUEUE_FILE='$QF' bash '$SELF' show | tail -1"
    check "add ends with the next action" "next: BUILD a" 0 q_fresh_add
    check "set ready ends with PUSH, not another BUILD" "next: PUSH a" 0 q_ready_first
    check "a second entry is not built before the first is pushed" "next: FINISH_BUILD a" 0 q_two_entries
    check "comments and blank lines are ignored" "BUILD d" 0 sh -c "printf '# note\n\n' >> '$QF'; QUEUE_FILE='$QF' bash '$SELF' next"

    # every branch of next, from a hand-written file
    fresh n1; mkdir -p "$(dirname "$QF")"; : > "$QF"
    check "DONE on an empty file" "DONE" 0 q next
    fresh n2; line 1 a - agent merged 3; line 2 b - owner dropped -
    check "DONE when every entry is merged or dropped" "DONE" 0 q next
    fresh n3; line 1 a - agent ready -; line 2 b - agent building -
    check "PUSH beats a building entry when nothing is pushed" "PUSH a" 0 q next
    fresh n4; line 1 a - agent merged 3; line 2 b a agent ready -
    check "PUSH a child whose parent is merged" "PUSH b" 0 q next
    fresh n5; line 1 a - agent pushed 3; line 2 b - agent ready -; line 3 c - agent building -; line 4 d - agent planned -
    check "FINISH_BUILD before BUILD while pushed" "FINISH_BUILD c" 0 q next
    fresh n6; line 1 a - agent pushed 3; line 2 b a agent planned -
    check "BUILD a child of the pushed entry" "BUILD b" 0 q next
    fresh n7; line 1 a - agent pushed 3; line 2 b - agent ready -; line 3 o - owner ready -
    check "WAIT when nothing is left to build" "WAIT a #3 agent" 0 q next
    fresh n8; line 1 a - agent merged 3; line 2 o - owner pushed 4
    check "WAIT names an owner entry" "WAIT o #4 owner" 0 q next
    fresh n9; line 1 a - agent dropped -; line 2 b a agent ready -
    check "HOLD a child of a dropped parent" "HOLD b after a" 0 q next
    fresh n10; line 1 a - agent dropped -; line 2 b a agent planned -
    check "HOLD a planned child of a dropped parent" "HOLD b after a" 0 q next
    fresh n11; line 1 a - agent planned -; line 2 o - owner ready -
    check "idle time builds the first entry, the owner entry waits" "BUILD a" 0 q next
    fresh n12; line 1 a - agent pushed 3; line 2 b a agent building -; line 3 c b agent planned -
    check "a grandchild waits until its parent is built" "FINISH_BUILD b" 0 q next
    fresh n13; line 1 a - agent pushed 3; line 2 b a agent planned -; line 3 c b agent planned -
    check "BUILD takes queue order" "BUILD b" 0 q next
    fresh n14; line 2 o - owner ready -; line 5 a - agent ready -
    check "an agent entry is pushed before an owner entry added earlier" "PUSH a" 0 q next
    fresh n15; line 1 a - agent merged 3; line 2 o - owner ready -
    check "PUSH an owner entry once everything ahead is merged" "PUSH o" 0 q next
    fresh n16; line 1 a - agent pushed 3; line 2 b - agent dropped -
    check "WAIT ignores dropped entries" "WAIT a #3 agent" 0 q next
    fresh n30; line 1 a - agent pushed 3; line 2 b a agent ready -
    check "dropping an entry that an open entry comes after is refused" "queue: refused: 'b' comes after 'a' and is open; dropping 'a' would hold it (merged is the status of a merged PR; or add --force)" 1 q set a status=dropped
    check "--force drops it" "set a: status dropped, pr 3, branch chore/a" 0 q set a --force status=dropped
    fresh n31; line 1 a - agent pushed 3; line 2 b a agent dropped -
    check "dropping an entry whose dependants are all closed is allowed" "set a: status dropped, pr 3, branch chore/a" 0 q set a status=dropped
    fresh n18; line 1 a - agent dropped -; line 2 b a agent ready -
    check "pushed refused while the parent is not merged" "queue: refused: the parent 'a' is not merged" 1 q set b status=pushed pr=5
    fresh n19; line 1 a - agent planned -; line 2 c - agent ready -
    check "pushed out of order" "queue: refused: 'a' comes first in the queue; 'c' is pushed after it is merged" 1 q set c status=pushed pr=9
    fresh n20; line 1 a - agent pushed 3; line 2 c - agent ready -
    check "a second pushed entry refused" "queue: refused: 'a' is pushed; one PR of the queue is pushed at a time" 1 q set c status=pushed pr=12
    check "a merged entry stays merged" "set a: status merged, pr 3, branch chore/a" 0 q set a status=merged
    check "setting merged again is no transition" "set a: status merged, pr 3, branch chore/a" 0 q set a status=merged
    fresh n21; line 1 a - agent building -
    check "a building entry is not pushed" "queue: refused: 'a' is building; only a ready entry is pushed" 1 q set a status=pushed pr=4
    fresh bad; mkdir -p "$tmp/bad"; printf 'x\ta\n' > "$QF"
    check "a malformed line exits 2" "queue: $QF:1 is not <order> <slug> <branch> <after> <kind> <status> <pr>" 2 q next
    fresh n17; line 1 a - agent pushed 3
    check "pushed entry can be set merged" "set a: status merged, pr 3, branch chore/a" 0 q set a status=merged
    check "after the merge: DONE" "DONE" 0 q next

    # The lock: six adds at once all land, each with its own order (without it, replacing the file loses
    # updates), and an add that cannot get the lock refuses instead of writing.
    fresh lk1; mkdir -p "$tmp/lk1"
    for s in a b c d e f; do q add "$s" --branch "chore/$s" >/dev/null 2>&1 & done
    wait
    out="$(q show 2>&1)"
    if [ "$(printf '%s\n' "$out" | grep -c ' planned ')" = 6 ]; then echo "ok   six concurrent adds all land"; else
        echo "FAIL six concurrent adds: expected 6 planned entries, got:" >&2; printf '%s\n' "$out" | sed 's/^/       /' >&2; fails=$((fails + 1)); fi
    check "the six concurrent adds have six different orders" "1 2 3 4 5 6" 0 sh -c "awk -F '\t' '{ print \$1 }' '$QF' | sort -n | tr '\n' ' ' | sed 's/ \$//'"
    fresh lk2; mkdir -p "$tmp/lk2"
    perl -e 'use Fcntl qw(:flock); open(my $f, ">>", $ARGV[0]) or exit 2; flock($f, LOCK_EX) or exit 2; sleep 4' "$QF.lock" &
    local holder=$!
    sleep 1
    out="$(TM_QUEUE_LOCK_WAIT=1 q add a --branch chore/a 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 1 ] && printf '%s' "$out" | grep -qF 'the queue file is locked by another add or set'; then echo "ok   an add that cannot get the lock refuses"; else
        echo "FAIL locked add: expected exit 1 and the refusal, got exit $rc: $out" >&2; fails=$((fails + 1)); fi
    if [ ! -e "$QF" ]; then echo "ok   the refused add wrote nothing"; else echo "FAIL the refused add wrote the file" >&2; fails=$((fails + 1)); fi
    wait "$holder"
    check "the same add works once the lock is free" "added a (agent, order 1)" 0 q add a --branch chore/a

    check "usage error exits 2" "usage: scripts/queue/queue.sh add <slug> --branch <branch> --task <file|-> [--after <slug>] [--kind agent|owner]" 2 bash "$SELF" bogus
    check "add without --branch exits 2" "usage: scripts/queue/queue.sh add <slug> --branch <branch> --task <file|-> [--after <slug>] [--kind agent|owner]" 2 q add x

    # `set` runs the workspace cleaner when an entry becomes merged or dropped (and only then), on the
    # workspace the queue file lives in; the cleaner's own guard refuses a directory without TrailMetrics/.
    fresh wsq
    local wsd="$tmp/wsq" mout mrc
    mkdir -p "$wsd/TrailMetrics" "$wsd/queue"; echo '#!/bin/sh' >"$wsd/start-agent.sh"
    QF="$wsd/queue/queue.tsv"
    printf 'Task.\n' >"$tmp/wsq-task.txt"
    q add a --branch chore/a --task "$tmp/wsq-task.txt" >/dev/null
    echo old >"$wsd/scratch-old.md"; touch -t 200001010000 "$wsd/scratch-old.md"
    echo old >"$wsd/mc-1.md"; touch -t 200001010000 "$wsd/mc-1.md"
    q set a status=building >/dev/null; q set a status=ready >/dev/null; q set a status=pushed pr=7 >/dev/null
    check "cleaner: setting an entry pushed does not run it" "kept" 0 sh -c "[ -e '$wsd/scratch-old.md' ] && echo kept"
    mout="$(q set a status=merged pr=7 2>&1)"
    check "cleaner: setting an entry merged deletes the old scratch file" "gone" 0 sh -c "[ ! -e '$wsd/scratch-old.md' ] && [ ! -e '$wsd/mc-1.md' ] && echo gone"
    check "cleaner: its summary line is printed before next" "clean-agent-workspace: removed 2 files, 0 review records; kept 1 fresh or in use, 0 unknown" 0 printf '%s\n' "$mout"
    check "cleaner: the queue file and the task text are kept" "kept" 0 sh -c "[ -e '$wsd/queue/queue.tsv' ] && [ -e '$wsd/queue/tasks/a.md' ] && echo kept"
    q add b --branch chore/b --task "$tmp/wsq-task.txt" >/dev/null
    echo old >"$wsd/older-than-b.md"; touch -t 200001010000 "$wsd/older-than-b.md"
    touch -t 200001010000 "$wsd/queue/tasks/b.md"
    out="$(q set b status=dropped 2>&1)"
    check "cleaner: dropping an entry runs it too" "gone" 0 sh -c "[ ! -e '$wsd/older-than-b.md' ] && echo gone"
    echo old >"$wsd/open-guard.md"; touch -t 200001010000 "$wsd/open-guard.md"
    q add c --branch chore/c --task "$tmp/wsq-task.txt" >/dev/null
    touch -t 200201010000 "$wsd/queue/tasks/c.md"
    echo old >"$wsd/used-by-c.md"; touch -t 200301010000 "$wsd/used-by-c.md"
    q add d --branch chore/d --task "$tmp/wsq-task.txt" >/dev/null
    q set d status=dropped >/dev/null
    check "cleaner: a file newer than the oldest open entry's text survives another entry's end" "kept" 0 sh -c "[ -e '$wsd/used-by-c.md' ] && echo kept"
    # A cleaner that fails is not silent: a warning on stderr, the set itself still succeeds.
    q set c status=building >/dev/null; q set c status=ready >/dev/null; q set c status=pushed pr=9 >/dev/null
    mkdir -p "$wsd/queue/subagent"; printf '2000-01-01T00:00:00\told\n' >"$wsd/queue/subagent/guard.log"; chmod 000 "$wsd/queue/subagent/guard.log"
    mout="$(q set c status=merged pr=9 2>&1)" && mrc=0 || mrc=$?
    chmod 600 "$wsd/queue/subagent/guard.log"
    check "cleaner: a failing cleaner does not fail the set" "0" 0 printf '%s\n' "$mrc"
    check "cleaner: a failing cleaner leaves a warning" "queue: warning: the workspace cleaner exited with status 1 (clean-agent-workspace: could not read queue/subagent/guard.log; it is not trimmed); run scripts/dev/clean-agent-workspace.sh to see it" 0 printf '%s\n' "$mout"
    check "cleaner: the set still prints its summary and next lines after a failing cleaner" "2" 0 sh -c "printf '%s\n' '$mout' | grep -c '^clean-agent-workspace: removed\|^next: '"
    check "cleaner: a set that is refused runs no cleaner" "quiet" 0 sh -c "QUEUE_FILE='$tmp/nowhere/queue.tsv' bash '$SELF' set zz status=merged pr=1 2>&1 | grep -q clean-agent || echo quiet"

    # The task text: required, copied next to the queue file, printed by `task`.
    fresh txt
    nt() { QUEUE_FILE="$QF" bash "$SELF" "$@"; }   # no common text file added
    check "add without --task is refused" "queue: refused: an entry needs its task text: --task <file> (or --task - for stdin)" 1 nt add a --branch chore/a
    check "a task file that is not there is refused" "queue: refused: the task text file '$tmp/nope.txt' does not exist" 1 nt add a --branch chore/a --task "$tmp/nope.txt"
    printf 'Other text.\n' > "$tmp/other.txt"
    : > "$tmp/empty.txt"; printf ' \n\t\n' > "$tmp/blank.txt"
    check "an empty task text is refused" "queue: refused: the task text is empty" 1 nt add a --branch chore/a --task "$tmp/empty.txt"
    check "a blank task text is refused" "queue: refused: the task text is empty" 1 nt add a --branch chore/a --task "$tmp/blank.txt"
    check "stdin text, empty, is refused" "queue: refused: the task text is empty" 1 sh -c "printf '' | QUEUE_FILE='$QF' bash '$SELF' add a --branch chore/a --task -"
    if [ ! -e "$QF" ] && [ ! -e "$(dirname "$QF")/tasks/a.md" ]; then echo "ok   a refused add writes neither the entry nor the text"; else echo "FAIL a refused add left a file" >&2; fails=$((fails + 1)); fi
    check "add with a task file" "added a (agent, order 1)" 0 nt add a --branch chore/a --task "$tmp/task.txt"
    check "the text is kept next to the queue file" "Scope: this file." 0 cat "$(dirname "$QF")/tasks/a.md"
    check "task prints it" "Do the thing." 0 nt task a
    check "add with the text on stdin" "added b (agent, order 2)" 0 sh -c "printf 'From stdin.\n' | QUEUE_FILE='$QF' bash '$SELF' add b --branch chore/b --task -"
    check "task prints the stdin text" "From stdin." 0 nt task b
    check "task of an unknown slug" "queue: refused: 'zz' is not in the queue" 1 nt task zz
    rm -f "$(dirname "$QF")/tasks/b.md"
    check "task of an entry whose text is gone" "queue: refused: 'b' has no task text ($(dirname "$QF")/tasks/b.md is missing)" 1 nt task b
    check "a refused add (duplicate slug) keeps the first text" "Do the thing." 0 sh -c "QUEUE_FILE='$QF' bash '$SELF' add a --branch chore/a2 --task '$tmp/other.txt' >/dev/null 2>&1; cat '$(dirname "$QF")/tasks/a.md' | head -1"
    # may-push: a push of an entry's branch only when the queue says PUSH for it, or for its open PR.
    fresh mp0
    check "may-push: no queue file, every branch is outside" "OUTSIDE chore/x" 0 q may-push chore/x
    fresh mp1; line 1 a - agent pushed 386; line 2 b - owner ready -; line 3 c - agent planned -; line 4 d - agent merged 380; line 5 e - agent dropped -
    check "may-push: a branch not in the queue is outside" "OUTSIDE feature/epic/route" 0 q may-push feature/epic/route
    check "may-push: the pushed entry takes new commits" "ALLOW a pushed #386" 0 q may-push chore/a
    check "may-push: refs/heads/ is ignored" "ALLOW a pushed #386" 0 q may-push refs/heads/chore/a
    check "may-push: a ready entry behind a PR waiting for the owner is refused (the #386/#387 case)" "REFUSE b is ready and the queue says 'BUILD c', not 'PUSH b'" 1 q may-push chore/b
    check "may-push: a planned entry is refused" "REFUSE c is planned and the queue says 'BUILD c', not 'PUSH c'" 1 q may-push chore/c
    check "may-push: a merged entry is refused" "REFUSE d is merged and the queue says 'BUILD c', not 'PUSH d'" 1 q may-push chore/d
    check "may-push: a dropped entry is refused" "REFUSE e is dropped and the queue says 'BUILD c', not 'PUSH e'" 1 q may-push chore/e
    fresh mp2; line 1 a - agent merged 386; line 2 b - owner ready -
    check "may-push: once the previous PR is merged, PUSH allows it" "ALLOW b PUSH" 0 q may-push chore/b
    fresh mp3; line 1 a - agent ready -; line 2 b - agent ready -
    check "may-push: only the entry that PUSH names" "REFUSE b is ready and the queue says 'PUSH a', not 'PUSH b'" 1 q may-push chore/b
    fresh mp4; line 1 a - agent building -
    check "may-push: a building entry is refused" "REFUSE a is building and the queue says 'FINISH_BUILD a', not 'PUSH a'" 1 q may-push chore/a
    fresh mpbad; mkdir -p "$tmp/mpbad"; printf 'x\ta\n' > "$QF"
    check "may-push: an unreadable queue file exits 2" "queue: $QF:1 is not <order> <slug> <branch> <after> <kind> <status> <pr>" 2 q may-push chore/a
    check "may-push without a branch is a usage error" "usage: scripts/queue/queue.sh add <slug> --branch <branch> --task <file|-> [--after <slug>] [--kind agent|owner]" 2 q may-push

    if [ "$fails" = 0 ]; then echo "queue.sh self-test: all passed"; else echo "queue.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || usage; self_test ;;
    add) shift; locked add "$@" ;;
    set) shift; locked set "$@" ;;
    show) [ "$#" = 1 ] || usage; cmd_show ;;
    task) [ "$#" = 2 ] || usage; cmd_task "$2" ;;
    next) [ "$#" = 1 ] || usage; cmd_next ;;
    may-push) [ "$#" = 2 ] || usage; cmd_may_push "$2" ;;
    *) usage ;;
esac
