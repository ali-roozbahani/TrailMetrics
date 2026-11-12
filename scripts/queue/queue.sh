#!/usr/bin/env bash
# The local, serial PR queue: which follow-up PR to build, push or wait for next. At most one PR of
# the queue is pushed (in CI) at a time; the others are built locally meanwhile, a dependent entry
# on its parent's local branch, and pushed against `main` only after its parent is merged. Entries
# that need the owner (kind `owner`: a protected path, ESCALATE_TO_HUMAN) come last.
#
#   scripts/queue/queue.sh add <slug> --branch <branch> [--after <slug>] [--kind agent|owner]
#   scripts/queue/queue.sh set <slug> <field>=<value>...     fields: status, pr, branch
#   scripts/queue/queue.sh show
#   scripts/queue/queue.sh next
#   scripts/queue/queue.sh --self-test
#
# The queue file: ${QUEUE_FILE:-$HOME/agent-workspace/queue/queue.tsv}, outside the repository
# (scripts/dev/clean-agent-workspace.sh always keeps the `queue/` folder). One tab-separated line per
# entry, lines starting with `#` ignored:
#   order  slug  branch  after  kind  status  pr
#   order   integer given by `add` (insertion order)    after   a slug, or `-`
#   kind    agent | owner                                status  planned | building | ready | pushed | merged | dropped
#   pr      the PR number, or `-`
# An entry is open while its status is not `merged` or `dropped`. Queue order: agent entries before
# owner entries, then by `order`.
#
# add refuses: a sixth open entry, a slug already in the file, an --after slug that is not in the
#   file or is dropped, an agent entry after an owner entry, a branch already in the file, a branch
#   without a feature/, bugfix/ or chore/ prefix. A new entry is `planned` with PR `-`.
# set refuses: an unknown slug, field or status, a PR that is not a number or `-`; status `pushed`
#   without a PR number, for an entry that is not `ready`, while another entry is pushed, for an
#   entry that is not the first open one in queue order, or whose parent is not merged; status
#   `merged` without a PR number, or for an entry that is not `pushed`.
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
# show prints the entries in queue order as aligned columns (awk only, no `column`).
#
# Exit: 0 ok, 1 refused (reason on stderr), 2 usage error or unreadable queue file.
# Bash 3.2 compatible.
set -u -o pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
QUEUE_FILE="${QUEUE_FILE:-$HOME/agent-workspace/queue/queue.tsv}"
MAX_OPEN=5
TAB="$(printf '\t')"
USAGE="usage: scripts/queue/queue.sh add <slug> --branch <branch> [--after <slug>] [--kind agent|owner]
       scripts/queue/queue.sh set <slug> <field>=<value>...   (status, pr, branch)
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

write_file() { # write_file <content file>: atomic replace
    local dir
    dir="$(dirname "$QUEUE_FILE")"
    mkdir -p "$dir" || die "cannot create $dir"
    cp -- "$1" "$QUEUE_FILE.tmp.$$" && mv -- "$QUEUE_FILE.tmp.$$" "$QUEUE_FILE" || die "cannot write $QUEUE_FILE"
}

cmd_add() {
    local slug="${1:-}" branch="" after="-" kind="agent" n open order pkind pstatus tmp
    [ -n "$slug" ] || usage
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --branch) [ "$#" -ge 2 ] || usage; branch="$2"; shift 2 ;;
            --after) [ "$#" -ge 2 ] || usage; after="$2"; shift 2 ;;
            --kind) [ "$#" -ge 2 ] || usage; kind="$2"; shift 2 ;;
            *) usage ;;
        esac
    done
    [ -n "$branch" ] || usage
    [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || refuse "slug '$slug' is not kebab-case"
    [[ "$branch" =~ ^(feature|bugfix|chore)/[A-Za-z0-9._/-]+$ ]] || refuse "branch '$branch' has no feature/, bugfix/ or chore/ prefix"
    case "$kind" in agent | owner) ;; *) refuse "kind '$kind' is not agent or owner" ;; esac
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
    open="$(entries | awk -F '\t' '$6 != "merged" && $6 != "dropped"' | wc -l | tr -d ' ')"
    [ "$open" -lt "$MAX_OPEN" ] || refuse "the queue already has $open open entries (maximum $MAX_OPEN)"
    order="$(entries | awk -F '\t' 'BEGIN { m = 0 } $1 > m { m = $1 } END { print m + 1 }')"
    tmp="$(mktemp)"
    { [ -f "$QUEUE_FILE" ] && cat -- "$QUEUE_FILE"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$order" "$slug" "$branch" "$after" "$kind" planned -; } > "$tmp"
    write_file "$tmp"
    rm -f -- "$tmp"
    if [ "$after" = - ]; then echo "added $slug ($kind, order $order)"; else echo "added $slug ($kind, order $order, after $after)"; fi
    print_next
}

# print_next: the line `next` would print, after the change just made.
print_next() { echo "next: $(cmd_next)"; }

cmd_set() {
    local slug="${1:-}" kv key val status pr branch tmp first other parent old
    [ -n "$slug" ] && [ "$#" -ge 2 ] || usage
    shift
    entries > /dev/null
    [ -n "$(field "$slug" 2)" ] || refuse "'$slug' is not in the queue"
    status="$(field "$slug" 6)"; old="$status"; pr="$(field "$slug" 7)"; branch="$(field "$slug" 3)"
    for kv in "$@"; do
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
    q() { QUEUE_FILE="$QF" bash "$SELF" "$@"; }
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
    check "sixth open entry refused" "queue: refused: the queue already has 5 open entries (maximum 5)" 1 q add d --branch chore/d
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
    check "dropped frees a slot" "set c: status dropped, pr -, branch chore/c" 0 q set c status=dropped
    check "add after a dropped entry refused" "queue: refused: --after 'c' is dropped" 1 q add d --branch chore/d --after c
    check "add into the freed slot" "added d (agent, order 6)" 0 q add d --branch chore/d
    check "a sixth open entry is still refused" "queue: refused: the queue already has 5 open entries (maximum 5)" 1 q add e --branch chore/e
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

    check "usage error exits 2" "usage: scripts/queue/queue.sh add <slug> --branch <branch> [--after <slug>] [--kind agent|owner]" 2 bash "$SELF" bogus
    check "add without --branch exits 2" "usage: scripts/queue/queue.sh add <slug> --branch <branch> [--after <slug>] [--kind agent|owner]" 2 q add x
    if [ "$fails" = 0 ]; then echo "queue.sh self-test: all passed"; else echo "queue.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]
    exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || usage; self_test ;;
    add) shift; cmd_add "$@" ;;
    set) shift; cmd_set "$@" ;;
    show) [ "$#" = 1 ] || usage; cmd_show ;;
    next) [ "$#" = 1 ] || usage; cmd_next ;;
    *) usage ;;
esac
