#!/usr/bin/env bash
# The record of the local pr-reviewer's report per commit, and the decision whether a push of that
# commit is allowed. Used by scripts/claude-hooks/require-local-review.sh (SubagentStop: record;
# PreToolUse: check); the hook is the only caller of `record`.
#
#   local-review-gate.sh record <run-on-sha>          the reviewer's final report on stdin
#   local-review-gate.sh disposition <sha> <disp>...  one argument per [important] finding, in order
#   local-review-gate.sh check <sha>                  exit 0 allowed, 1 blocked (reason on stderr)
#   local-review-gate.sh --self-test
#
# `record` accepts a report only if line 1 is `VERDICT: APPROVE|CHANGES|ESCALATE_TO_HUMAN`, line 2 is
# `REVIEWED_SHA: <full sha>` and that sha equals <run-on-sha> (the sha the reviewer was started on,
# which the hook reads from the reviewer's own transcript) and names a commit of this repository.
# The [blocking] and [important] counts are parsed here from the numbered finding lines
# (`<n>. [blocking]`, `<n>. [important]`), never given by the caller. `check` also blocks on any line
# that mentions `[blocking]` or `[important]` and is not a numbered finding line (`<n>. [blocking]`,
# `<n>. [important]` or `<n>. [note]` at the start, leading spaces allowed): a bullet, a heading or
# prose ("a finding line the gate cannot parse"), so a finding in another format never counts as
# zero. A numbered `[note]` that quotes a tag in its text is fine; a numbered `[blocking]` line that
# quotes `[important]` is one blocking finding.
#
# `check <sha>` allows when the recorded review of exactly that sha has verdict APPROVE, or
# ESCALATE_TO_HUMAN, with zero [blocking] findings, and every [important] finding has a
# disposition recorded for that report: `fixed in <sha>` (the reviewed commit or an ancestor of it,
# not on origin/main), `board record <slug>` or `rejected: <reason>` (`human check` is not one).
# A review of another commit never counts.
#
# Records: ${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}/<sha>/report (latest report),
# report.<n> (earlier reports of the same sha, kept), dispositions (first line `report <sha256>`,
# then one disposition per line). Outside the repo; nothing here deletes a record.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEWS_DIR="${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}"
SHA_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'

die() { echo "local-review-gate: $*" >&2; exit 1; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# count_tag <file> <tag>: numbered finding lines with that tag.
count_tag() {
    local n
    n="$(grep -cE "^[[:space:]]*[0-9]+\.[[:space:]]+\[$2\]" "$1" || true)"
    echo "${n:-0}"
}

cmd_record() {
    local run_on="${1:-}" tmp l1 l2 verdict reviewed dir n
    [[ "$run_on" =~ $SHA_RE ]] || die "record: usage: record <full run-on sha> < report"
    tmp="$(mktemp)"
    trap 'rm -f -- "$tmp"' RETURN
    # A report is short; refuse anything large instead of storing it.
    head -c 200000 >"$tmp"
    l1="$(sed -n 1p "$tmp")"
    l2="$(sed -n 2p "$tmp")"
    [[ "$l1" =~ ^VERDICT:\ (APPROVE|CHANGES|ESCALATE_TO_HUMAN)$ ]] || die "record: line 1 is not 'VERDICT: APPROVE|CHANGES|ESCALATE_TO_HUMAN' (NO_VERDICT and free text are never recorded)"
    verdict="${BASH_REMATCH[1]}"
    [[ "$l2" =~ ^REVIEWED_SHA:\ ([0-9a-f]{40}|[0-9a-f]{64})$ ]] || die "record: line 2 is not 'REVIEWED_SHA: <full sha>'"
    reviewed="${BASH_REMATCH[1]}"
    [ "$reviewed" = "$run_on" ] || die "record: REVIEWED_SHA ${reviewed:0:12} differs from the sha the reviewer was run on ${run_on:0:12}"
    git cat-file -e "$run_on^{commit}" 2>/dev/null || die "record: $run_on is not a commit of this repository"
    dir="$REVIEWS_DIR/$run_on"
    mkdir -p "$dir"
    if [ -e "$dir/report" ]; then
        n=1
        while [ -e "$dir/report.$n" ]; do n=$((n + 1)); done
        mv -- "$dir/report" "$dir/report.$n"
    fi
    cp -- "$tmp" "$dir/report"
    echo "recorded ${run_on:0:12}: $verdict, blocking $(count_tag "$dir/report" blocking), important $(count_tag "$dir/report" important)"
}

# count_unparsed <file>: lines that mention [blocking] or [important] and are not a numbered finding line.
count_unparsed() {
    local n
    n="$(grep -E '\[(blocking|important)\]' "$1" | grep -vcE '^[[:space:]]*[0-9]+\.[[:space:]]+\[(blocking|important|note)\]' || true)"
    echo "${n:-0}"
}

# fixed_in_ok <sha-or-prefix> <reviewed sha>: a commit that is the reviewed commit or its ancestor and
# is not on origin/main. Without origin/main there is nothing to compare with: refused.
fixed_in_ok() {
    local full
    full="$(git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null)" || return 1
    git rev-parse --verify --quiet origin/main >/dev/null 2>&1 || return 1
    git merge-base --is-ancestor "$full" "$2" 2>/dev/null || return 1
    ! git merge-base --is-ancestor "$full" origin/main 2>/dev/null
}

# valid_disposition <disposition> <reviewed sha>
valid_disposition() {
    local d="$1"
    if [[ "$d" =~ ^fixed\ in\ ([0-9a-f]{7,40})$ ]]; then
        fixed_in_ok "${BASH_REMATCH[1]}" "$2"
    elif [[ "$d" =~ ^board\ record\ [a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        return 0
    elif [[ "$d" =~ ^rejected:\ .{15,}$ ]]; then
        return 0
    else
        return 1
    fi
}

cmd_disposition() {
    local sha="${1:-}" dir imp d i=0
    [[ "$sha" =~ $SHA_RE ]] || die "disposition: usage: disposition <full sha> <disposition>..."
    shift
    dir="$REVIEWS_DIR/$sha"
    [ -f "$dir/report" ] || die "disposition: no review recorded for ${sha:0:12}"
    imp="$(count_tag "$dir/report" important)"
    [ "$#" -eq "$imp" ] || die "disposition: the review of ${sha:0:12} has $imp [important] finding(s), got $# disposition(s)"
    for d in "$@"; do
        i=$((i + 1))
        valid_disposition "$d" "$sha" || die "disposition $i is not 'fixed in <sha>' (the reviewed commit or an ancestor of it, not on origin/main), 'board record <slug>' or 'rejected: <reason of 15+ characters>': $d"
    done
    {
        echo "report $(sha256_of "$dir/report")"
        for d in "$@"; do echo "$d"; done
    } >"$dir/dispositions.new"
    if [ -e "$dir/dispositions" ]; then
        i=1
        while [ -e "$dir/dispositions.$i" ]; do i=$((i + 1)); done
        mv -- "$dir/dispositions" "$dir/dispositions.$i"
    fi
    mv -- "$dir/dispositions.new" "$dir/dispositions"
    echo "dispositions recorded for ${sha:0:12}: $imp"
}

block() { echo "Blocked: $*" >&2; exit 1; }

cmd_check() {
    local sha="${1:-}" dir report verdict reviewed blocking imp unparsed lines want got line n=0
    [[ "$sha" =~ $SHA_RE ]] || die "check: usage: check <full sha>"
    dir="$REVIEWS_DIR/$sha"
    report="$dir/report"
    [ -f "$report" ] || block "no local review is recorded for ${sha:0:12}. Run the pr-reviewer on this exact commit (tm-pr-review, \"Orchestrator's part\"); a review of another commit does not count."
    # Re-validate the stored report: a hand-placed or altered file must not pass.
    [[ "$(sed -n 1p "$report")" =~ ^VERDICT:\ (APPROVE|CHANGES|ESCALATE_TO_HUMAN)$ ]] \
        || block "the recorded review of ${sha:0:12} has no VERDICT line (UNKNOWN verdict)."
    verdict="${BASH_REMATCH[1]}"
    [[ "$(sed -n 2p "$report")" =~ ^REVIEWED_SHA:\ ([0-9a-f]{40}|[0-9a-f]{64})$ ]] \
        || block "the recorded review of ${sha:0:12} has no REVIEWED_SHA line."
    reviewed="${BASH_REMATCH[1]}"
    [ "$reviewed" = "$sha" ] || block "the recorded review is of ${reviewed:0:12}, not of ${sha:0:12} (wrong SHA)."
    [ "$verdict" != CHANGES ] || block "the local review of ${sha:0:12} is CHANGES. Fix the findings as a new commit and review the new HEAD."
    blocking="$(count_tag "$report" blocking)"
    imp="$(count_tag "$report" important)"
    unparsed="$(count_unparsed "$report")"
    [ "$unparsed" -eq 0 ] \
        || block "the local review of ${sha:0:12} has a finding line the gate cannot parse: $unparsed line(s) mention [blocking] or [important] without being a numbered finding line ('<n>. [blocking]', '<n>. [important]' or '<n>. [note]'). Ask the reviewer again, in the report format of tm-pr-review."
    [ "$blocking" -eq 0 ] || block "the local review of ${sha:0:12} has $blocking [blocking] finding(s). Fix them as a new commit and review the new HEAD."
    if [ "$imp" -gt 0 ]; then
        [ -f "$dir/dispositions" ] || block "the local review of ${sha:0:12} has $imp [important] finding(s) and no dispositions are recorded. Run: scripts/local-review-gate.sh disposition ${sha} '<fixed in <sha> | board record <slug> | rejected: <reason>>' ... ($imp arguments, in report order)."
        want="report $(sha256_of "$report")"
        [ "$(sed -n 1p "$dir/dispositions")" = "$want" ] || block "the dispositions of ${sha:0:12} belong to an earlier report of that commit. Record them again for the latest review."
        lines="$(sed -n '2,$p' "$dir/dispositions")"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            n=$((n + 1))
            valid_disposition "$line" "$sha" || block "disposition $n of ${sha:0:12} is not 'fixed in <sha>' (the reviewed commit or an ancestor of it, not on origin/main), 'board record <slug>' or 'rejected: <reason>': $line"
        done <<<"$lines"
        got="$n"
        [ "$got" -eq "$imp" ] || block "the review of ${sha:0:12} has $imp [important] finding(s) but $got disposition(s) are recorded."
    fi
    echo "allowed: ${sha:0:12} $verdict, blocking 0, important $imp (all disposed)"
}

self_test() {
    local fx tmp fails=0 repo sha parent unrelated rc name want out mainc later orphan
    fx="$SCRIPT_DIR/local-review-gate-fixtures"
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' RETURN
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp" LOCAL_REVIEWS_DIR="$tmp/reviews"
    repo="$tmp/repo"
    git init -q "$repo"
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name t
    git -C "$repo" commit -q --allow-empty -m zero
    mainc="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" update-ref refs/remotes/origin/main "$mainc"
    git -C "$repo" commit -q --allow-empty -m one
    parent="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" commit -q --allow-empty -m two
    sha="$(git -C "$repo" rev-parse HEAD)"
    unrelated="$(printf '%040d' 7)"
    later="$(git -C "$repo" commit-tree -p "$sha" -m three "$sha^{tree}")"
    orphan="$(git -C "$repo" commit-tree -m orphan "$sha^{tree}")"
    cd "$repo"

    # fixture <name> <sha>: the fixture report with @SHA@ replaced.
    fixture() { sed "s/@SHA@/$2/g" "$fx/$1.md"; }
    # run <name> <want exit> <command...>: compare the script's own exit code.
    run() {
        name="$1"; want="$2"; shift 2
        rc=0
        out="$("$@" 2>&1 >/dev/null)" || rc=$?
        if [ "$rc" = "$want" ]; then
            echo "ok   $name (exit $rc)"
        else
            echo "FAIL $name: expected exit $want, got $rc: $out" >&2
            fails=$((fails + 1))
        fi
    }
    rec() { fixture "$1" "$2" | bash "$SCRIPT_DIR/local-review-gate.sh" record "$3"; }
    chk() { bash "$SCRIPT_DIR/local-review-gate.sh" check "$1"; }
    disp() { bash "$SCRIPT_DIR/local-review-gate.sh" disposition "$@"; }
    reset() { rm -rf -- "$LOCAL_REVIEWS_DIR"; }

    reset; run "no review recorded blocks" 1 chk "$sha"
    reset; rec approve "$sha" "$sha" >/dev/null; run "APPROVE allows" 0 chk "$sha"
    reset; rec escalate-no-blocking "$sha" "$sha" >/dev/null; run "ESCALATE_TO_HUMAN without blocking allows" 0 chk "$sha"
    reset; rec escalate-blocking "$sha" "$sha" >/dev/null; run "ESCALATE_TO_HUMAN with blocking blocks" 1 chk "$sha"
    reset; rec changes "$sha" "$sha" >/dev/null; run "CHANGES blocks" 1 chk "$sha"
    reset; run "report with no VERDICT line is not recorded" 1 rec no-verdict "$sha" "$sha"
    reset; run "report with no VERDICT line leaves nothing to check" 1 chk "$sha"
    reset; rec approve "$parent" "$parent" >/dev/null; run "review of the parent commit does not allow HEAD" 1 chk "$sha"
    reset; run "forged REVIEWED_SHA (not the run-on sha) is not recorded" 1 rec approve "$unrelated" "$sha"
    reset; run "run-on sha that is no commit is not recorded" 1 rec approve "$unrelated" "$unrelated"
    # A hand-placed file keyed by the sha but whose REVIEWED_SHA is another commit.
    reset; mkdir -p "$LOCAL_REVIEWS_DIR/$sha"; fixture approve "$parent" >"$LOCAL_REVIEWS_DIR/$sha/report"
    run "hand-placed report of another sha blocks" 1 chk "$sha"
    reset; mkdir -p "$LOCAL_REVIEWS_DIR/$sha"; printf 'APPROVE\n' >"$LOCAL_REVIEWS_DIR/$sha/report"
    run "hand-placed report without VERDICT line blocks" 1 chk "$sha"

    reset; rec two-important "$sha" "$sha" >/dev/null
    run "two importants, none disposed blocks" 1 chk "$sha"
    run "two importants, one disposition is refused" 1 disp "$sha" "board record some-slug"
    run "two importants, one disposition leaves the check blocked" 1 chk "$sha"
    run "human check is not a disposition" 1 disp "$sha" "board record some-slug" "human check"
    run "fixed in an unknown commit is refused" 1 disp "$sha" "board record some-slug" "fixed in deadbee"
    run "rejected without a reason is refused" 1 disp "$sha" "board record some-slug" "rejected:"
    run "two valid dispositions are recorded" 0 disp "$sha" "board record some-slug" "rejected: the null case cannot happen, see the guard in start()"
    run "two importants, both disposed allows" 0 chk "$sha"
    # A new report of the same commit invalidates the dispositions of the old one.
    rec three-important "$sha" "$sha" >/dev/null
    run "dispositions of an earlier report do not carry over" 1 chk "$sha"

    reset; rec three-important "$sha" "$sha" >/dev/null
    run "three valid dispositions are recorded" 0 disp "$sha" "fixed in ${parent:0:7}" "board record flake-some-test" "rejected: the reviewer misread the diff, line is in a comment"
    run "three importants, three dispositions allows" 0 chk "$sha"
    reset; rec approve "$sha" "$sha" >/dev/null
    run "no importants: a disposition is refused" 1 disp "$sha" "board record x-y"
    # fixed in <commit>: the reviewed commit or an ancestor of it, not on origin/main.
    reset; rec two-important "$sha" "$sha" >/dev/null
    run "fixed in the reviewed commit is recorded" 0 disp "$sha" "fixed in ${sha:0:7}" "board record some-slug"
    run "fixed in a descendant of the reviewed commit is refused" 1 disp "$sha" "fixed in ${later:0:7}" "board record some-slug"
    run "fixed in an unrelated commit is refused" 1 disp "$sha" "fixed in ${orphan:0:7}" "board record some-slug"
    run "fixed in a commit on origin/main is refused" 1 disp "$sha" "fixed in ${mainc:0:7}" "board record some-slug"
    # check re-validates hand-placed dispositions the same way.
    forge() { { echo "report $(sha256_of "$LOCAL_REVIEWS_DIR/$sha/report")"; printf '%s\n' "$@"; } >"$LOCAL_REVIEWS_DIR/$sha/dispositions"; }
    forge "fixed in ${parent:0:7}" "board record some-slug"; run "check: fixed in an ancestor allows" 0 chk "$sha"
    forge "fixed in ${later:0:7}" "board record some-slug"; run "check: fixed in a descendant blocks" 1 chk "$sha"
    forge "fixed in ${orphan:0:7}" "board record some-slug"; run "check: fixed in an unrelated commit blocks" 1 chk "$sha"
    forge "fixed in ${mainc:0:7}" "board record some-slug"; run "check: fixed in a commit on origin/main blocks" 1 chk "$sha"
    # Fail closed on finding lines the strict parser does not see.
    reset; rec bullet-blocking "$sha" "$sha" >/dev/null; run "a bullet-formatted [blocking] finding blocks" 1 chk "$sha"
    reset; rec bullet-important "$sha" "$sha" >/dev/null; run "a bullet-formatted [important] finding blocks" 1 chk "$sha"
    reset; rec prose-mention "$sha" "$sha" >/dev/null; run "a prose line mentioning a tag blocks" 1 chk "$sha"
    reset; rec prose-no-findings "$sha" "$sha" >/dev/null; run "the prose line 'No [blocking] findings.' blocks" 1 chk "$sha"
    reset; rec note-quotes-blocking "$sha" "$sha" >/dev/null; run "a numbered [note] that quotes [blocking] allows" 0 chk "$sha"
    reset; out="$(rec blocking-quotes-important "$sha" "$sha")"
    case "$out" in *"blocking 1, important 0") echo "ok   a numbered [blocking] line that quotes [important] is counted once, as blocking" ;; *) echo "FAIL blocking line quoting [important] is not counted once: $out" >&2; fails=$((fails + 1)) ;; esac
    [ -f "$LOCAL_REVIEWS_DIR/$sha/report" ] && echo "ok   records are kept" || { echo "FAIL records are kept" >&2; fails=$((fails + 1)); }

    if [ "$fails" -ne 0 ]; then
        echo "local-review-gate.sh self-test: $fails failed" >&2
        return 1
    fi
    echo "local-review-gate.sh self-test: all passed"
}

case "${1:-}" in
    --self-test) self_test; exit $? ;;
    record) shift; cmd_record "$@" ;;
    disposition) shift; cmd_disposition "$@" ;;
    check) shift; cmd_check "$@" ;;
    *) echo "usage: $0 record <run-on-sha> | disposition <sha> <disp>... | check <sha> | --self-test" >&2; exit 2 ;;
esac
