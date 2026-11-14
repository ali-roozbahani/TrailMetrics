#!/usr/bin/env bash
# Deletes the agent workspace's files of finished work: PR description drafts, commit messages,
# merge-check comments, reviewer messages, gate logs and old local review records. Run at the
# start of a task, after main is synced (tm-agent-loop, "Preconditions"); never mid-task.
#
# Usage:
#   scripts/dev/clean-agent-workspace.sh [--dry-run] [<workspace dir>]   (default ~/agent-workspace)
#   scripts/dev/clean-agent-workspace.sh --self-test
#
# Guard: refuses (exit 2) unless <workspace dir> holds the directory `TrailMetrics/` and the file
# `start-agent.sh`. Only the entries directly inside the dir are looked at, symlinks are never
# followed or deleted, and `TrailMetrics/` is never entered.
#
# Deleted when older than 3 days (modification time), regular files only:
#   pr-body-*  commit-*  merge-check-*  review-msg-*  gate-*.log
# Always kept: TrailMetrics/, start-agent.sh, main-ci-ack (state of scripts/main-ci-status.sh --ack),
#   hook-debug/ (kept to its newest 10 files by scripts/claude-hooks/require-local-review.sh),
#   queue/ itself, its queue file (queue.tsv, which `add` and `set` use for the slugs and the order),
#   its lock files and the folder structure; what is cleaned inside it is listed next.
#
# queue/ (the PR queue's folder, scripts/queue/queue.sh), cleaned on every run:
#   - tasks/<slug>.md, the task text of an entry: deleted only when the queue file's row for <slug> says
#     `merged` or `dropped` (read right before the delete) AND the text is older than 3 days. The text of
#     an open entry (planned, building, ready, pushed) is never deleted, however old it is. A text whose
#     slug has no row, and any other name, is kept and printed as unknown. If the queue file is missing,
#     is a link or is not a well-formed queue (every line a comment, blank, or 7 tab-separated fields with
#     a known status), no text is deleted at all.
#   - subagent/guard.log (scripts/subagent/guard.sh) and locks/heavy-run.log (scripts/heavy-run.sh): the
#     lines whose leading timestamp (local time, `YYYY-MM-DDTHH:MM:SS`) is older than 3 days are removed;
#     a line without such a timestamp is kept; a log with nothing old is not touched. The rewrite is not
#     safe against a writer at the same moment, which is why this runs at the start of a task, never
#     mid-task: a line appended while it runs may be lost, and a log is not a decision input.
# Any other entry, a symlink or a pattern name that is not a regular file is kept and printed as
#   `kept, unknown: <name>`.
#
# local-reviews/ (the records of scripts/local-review-gate.sh, one directory per SHA): a record is
# deleted only when it is older than 3 days (its directory and every file directly in it) AND its
# SHA is neither the head of an open PR (`gh pr list --state open`, run in TrailMetrics/) nor the
# HEAD of a local branch of TrailMetrics/ that is not merged into origin/main. If `gh` or `git`
# fails, or gh returns 200 heads (the list may be cut), no record is deleted. An entry that is
# not a SHA-named directory is kept as unknown.
#
# Output: `deleted <name>` (with --dry-run: `would delete <name>`) per deleted file or record,
# `trimmed <log>: removed <n> lines older than 3 days` (`would trim` with --dry-run) per trimmed log,
# `kept, unknown: <name>` per unknown entry, then one summary line (a deleted task text counts as a file,
# a kept one as fresh or in use; trimmed lines are not in it):
#   clean-agent-workspace: removed <n> files, <m> review records; kept <f> fresh or in use, <u> unknown
# (`would remove` with --dry-run). --dry-run deletes nothing.
#
# Exit codes: 0 done; 1 a deletion failed; 2 usage error or the guard refused the dir.

set -euo pipefail

MAX_AGE_SECONDS=$((3 * 86400))
SHA_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'
GH_LIMIT=200

# GNU stat's -f means file-system status, so the flavour is chosen once, not by trying both.
if stat -c %Y / >/dev/null 2>&1; then STAT_MTIME=(stat -c %Y); else STAT_MTIME=(stat -f %m); fi
mtime_of() { # seconds since the epoch, of the entry itself (never a symlink's target)
    "${STAT_MTIME[@]}" "$1"
}

# The logs' timestamps are local time, `YYYY-MM-DDTHH:MM:SS`; GNU date takes -d @epoch, BSD date -r epoch.
if date -d @0 >/dev/null 2>&1; then
    time_string() { date -d "@$1" +%Y-%m-%dT%H:%M:%S; }
else
    time_string() { date -r "$1" +%Y-%m-%dT%H:%M:%S; }
fi

is_old() { # is_old <path>: older than MAX_AGE_SECONDS
    local m
    m="$(mtime_of "$1")" || return 1
    [ $((NOW - m)) -gt "$MAX_AGE_SECONDS" ]
}

record_is_old() { # the record dir and every entry directly in it are old
    local e
    is_old "$1" || return 1
    for e in "$1"/* "$1"/.[!.]*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        is_old "$e" || return 1
    done
    return 0
}

remove() { # remove <path> <name> <kind: file|record>
    if [ "$DRY_RUN" = 1 ]; then
        echo "would delete $2"
    elif rm -rf -- "$1"; then
        echo "deleted $2"
    else
        echo "clean-agent-workspace: could not delete $2" >&2
        FAILED=1
        return 0
    fi
    if [ "$3" = record ]; then RECORDS=$((RECORDS + 1)); else FILES=$((FILES + 1)); fi
}

# The SHAs whose records are kept whatever their age; fails when they cannot be known.
kept_shas() {
    local repo="$1" heads b
    heads="$(cd "$repo" && gh pr list --state open --limit "$GH_LIMIT" --json headRefOid --jq '.[].headRefOid')" || return 1
    if [ -n "$heads" ]; then
        while IFS= read -r b; do [[ "$b" =~ $SHA_RE ]] || return 1; done <<<"$heads"
        [ "$(printf '%s\n' "$heads" | wc -l | tr -d ' ')" -lt "$GH_LIMIT" ] || return 1
        printf '%s\n' "$heads"
    fi
    git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null || return 1
    heads="$(git -C "$repo" for-each-ref --format='%(objectname)' refs/heads/)" || return 1
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        git -C "$repo" merge-base --is-ancestor "$b" refs/remotes/origin/main && continue
        echo "$b"
    done <<<"$heads"
}

# queue_file_ok <file>: a regular file, no link, that is a well-formed queue (see the header).
queue_file_ok() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    awk -F '\t' '/^#/ || /^[[:space:]]*$/ { next }
        NF != 7 || $6 !~ /^(planned|building|ready|pushed|merged|dropped)$/ { bad = 1 }
        END { exit bad }' "$1"
}

queue_status_of() { # queue_status_of <queue file> <slug>: the status in the slug's row, or nothing
    awk -F '\t' -v s="$2" '!/^#/ && NF == 7 && $2 == s { print $6 }' "$1"
}

clean_task_texts() { # clean_task_texts <tasks dir> <queue file>
    local dir="$1" qf="$2" e name slug st
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
    if ! queue_file_ok "$qf"; then
        echo "clean-agent-workspace: the queue file could not be read as a queue; no task text deleted" >&2
        return 0
    fi
    for e in "$dir"/*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        name="${e##*/}"
        if [ -L "$e" ] || [ ! -f "$e" ] || ! [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
            echo "kept, unknown: queue/tasks/$name"
            UNKNOWN=$((UNKNOWN + 1))
            continue
        fi
        slug="${name%.md}"
        st="$(queue_status_of "$qf" "$slug")"
        if [ -z "$st" ]; then
            echo "kept, unknown: queue/tasks/$name"
            UNKNOWN=$((UNKNOWN + 1))
        elif { [ "$st" = merged ] || [ "$st" = dropped ]; } && is_old "$e"; then
            remove "$e" "queue/tasks/$name" file
        else
            FRESH=$((FRESH + 1))
        fi
    done
}

# trim_log <log file> <name>: remove the lines older than MAX_AGE_SECONDS (the leading timestamp is
# compared with CUTOFF, in the same local-time format); a line without a timestamp is kept.
trim_log() {
    local f="$1" name="$2" counts total keep tmp
    [ -f "$f" ] && [ ! -L "$f" ] || return 0
    counts="$(awk -F '\t' -v c="$CUTOFF" '
        { t++ }
        $1 >= c || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ { k++ }
        END { print t + 0, k + 0 }' "$f")" || {
        echo "clean-agent-workspace: could not read $name; it is not trimmed" >&2
        FAILED=1
        return 0
    }
    total="${counts% *}"; keep="${counts#* }"
    [ "$total" -gt "$keep" ] || return 0
    if [ "$DRY_RUN" = 1 ]; then
        echo "would trim $name: removed $((total - keep)) lines older than 3 days"
        return 0
    fi
    tmp="$(mktemp "$f.tmp.XXXXXX")" || { FAILED=1; return 0; }
    if awk -F '\t' -v c="$CUTOFF" '
        $1 >= c || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ { print }' "$f" > "$tmp" && mv -f "$tmp" "$f"; then
        echo "trimmed $name: removed $((total - keep)) lines older than 3 days"
    else
        rm -f -- "$tmp"
        echo "clean-agent-workspace: could not trim $name" >&2
        FAILED=1
    fi
}

clean_queue() { # the queue/ folder: task texts of finished entries, old lines of the two logs
    local q="$1"
    [ -d "$q" ] && [ ! -L "$q" ] || return 0
    clean_task_texts "$q/tasks" "$q/queue.tsv"
    trim_log "$q/subagent/guard.log" "queue/subagent/guard.log"
    trim_log "$q/locks/heavy-run.log" "queue/locks/heavy-run.log"
}

clean_records() {
    local dir="$1" keep e name
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
    if ! keep="$(kept_shas "$WS/TrailMetrics")"; then
        echo "clean-agent-workspace: the open PR heads or unmerged branch heads could not be read; no review record deleted" >&2
        return 0
    fi
    for e in "$dir"/* "$dir"/.[!.]*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        name="${e##*/}"
        if [ -L "$e" ] || [ ! -d "$e" ] || ! [[ "$name" =~ $SHA_RE ]]; then
            echo "kept, unknown: local-reviews/$name"
            UNKNOWN=$((UNKNOWN + 1))
            continue
        fi
        if grep -qxF -- "$name" <<<"$keep" || ! record_is_old "$e"; then
            FRESH=$((FRESH + 1))
            continue
        fi
        remove "$e" "local-reviews/$name" record
    done
}

clean() {
    local e name
    if [ ! -d "$WS/TrailMetrics" ] || [ -L "$WS/TrailMetrics" ] || [ ! -f "$WS/start-agent.sh" ] || [ -L "$WS/start-agent.sh" ]; then
        echo "clean-agent-workspace: refused: $WS does not hold TrailMetrics/ and start-agent.sh" >&2
        return 2
    fi
    NOW="$(date +%s)" FILES=0 RECORDS=0 FRESH=0 UNKNOWN=0 FAILED=0
    CUTOFF="$(time_string $((NOW - MAX_AGE_SECONDS)))"
    for e in "$WS"/* "$WS"/.[!.]*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        name="${e##*/}"
        if [ ! -L "$e" ]; then
            case "$name" in
                TrailMetrics | start-agent.sh | main-ci-ack | hook-debug) continue ;;
                queue) clean_queue "$e"; continue ;;
                local-reviews) if [ -d "$e" ]; then clean_records "$e"; continue; fi ;;
                pr-body-* | commit-* | merge-check-* | review-msg-* | gate-*.log)
                    if [ -f "$e" ]; then
                        if is_old "$e"; then remove "$e" "$name" file; else FRESH=$((FRESH + 1)); fi
                        continue
                    fi
                    ;;
            esac
        fi
        echo "kept, unknown: $name"
        UNKNOWN=$((UNKNOWN + 1))
    done
    local verb=removed
    [ "$DRY_RUN" = 1 ] && verb="would remove"
    echo "clean-agent-workspace: $verb $FILES files, $RECORDS review records; kept $FRESH fresh or in use, $UNKNOWN unknown"
    [ "$FAILED" = 0 ] || return 1
}

self_test() {
    local script tmp ws stub repo fails=0 out rc sha_open sha_branch sha_merged sha_old OLD=200001010000
    script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' RETURN
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

    # A stub `gh` that prints the open PR heads from $STUB_GH_HEADS; STUB_GH_FAIL makes it fail.
    stub="$tmp/bin"
    mkdir -p "$stub"
    cat >"$stub/gh" <<'STUB'
#!/usr/bin/env bash
if [ -n "${STUB_GH_FAIL:-}" ]; then echo "stub gh: simulated failure" >&2; exit 1; fi
cat "$STUB_GH_HEADS"
STUB
    chmod +x "$stub/gh"

    check() { # check <description> <condition...>
        local d="$1"; shift
        if "$@"; then echo "ok   $d"; else echo "FAIL $d" >&2; fails=$((fails + 1)); fi
    }
    gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
    there() { [ -e "$1" ] || [ -L "$1" ]; }

    # make_ws <dir>: a fake workspace with old and fresh files of every pattern, the protected
    # names, an unknown file, a symlink and four old review records.
    make_ws() {
        local w="$1" p r
        mkdir -p "$w/TrailMetrics" "$w/hook-debug" "$w/local-reviews" "$w/queue"
        echo old >"$w/queue/queue.tsv"; touch -t "$OLD" "$w/queue/queue.tsv" "$w/queue"
        repo="$w/TrailMetrics"
        git init -q -b main "$repo"
        git -C "$repo" config user.email t@example.com
        git -C "$repo" config user.name t
        git -C "$repo" commit -q --allow-empty -m init
        sha_merged="$(git -C "$repo" rev-parse HEAD)"
        git -C "$repo" update-ref refs/remotes/origin/main "$sha_merged"
        git -C "$repo" switch -q -c feature/open
        git -C "$repo" commit -q --allow-empty -m open
        sha_open="$(git -C "$repo" rev-parse HEAD)"
        git -C "$repo" switch -q -c chore/unmerged
        git -C "$repo" commit -q --allow-empty -m unmerged
        sha_branch="$(git -C "$repo" rev-parse HEAD)"
        sha_old="$(printf 'a%.0s' $(seq 40))"
        git -C "$repo" switch -q main
        echo "$sha_open" >"$tmp/heads"
        echo '#!/bin/sh' >"$w/start-agent.sh"
        echo 1 >"$w/main-ci-ack"
        for p in pr-body-x.md commit-x.txt merge-check-1.md review-msg-x.txt gate-x.log; do
            echo old >"$w/$p"; touch -t "$OLD" "$w/$p"
        done
        for p in pr-body-fresh.md commit-fresh.txt merge-check-fresh.md review-msg-fresh.txt gate-fresh.log; do
            echo new >"$w/$p"
        done
        echo old >"$w/gate-x.txt"; touch -t "$OLD" "$w/gate-x.txt" # not gate-*.log: unknown
        echo old >"$w/notes.md"; touch -t "$OLD" "$w/notes.md"
        echo old >"$tmp/target"; touch -t "$OLD" "$tmp/target"
        ln -s "$tmp/target" "$w/pr-body-link.md"
        touch -t "$OLD" "$w/main-ci-ack" "$w/start-agent.sh"
        for r in "$sha_merged" "$sha_open" "$sha_branch" "$sha_old"; do
            mkdir -p "$w/local-reviews/$r"; echo VERDICT >"$w/local-reviews/$r/report"
            touch -t "$OLD" "$w/local-reviews/$r/report" "$w/local-reviews/$r"
        done
        mkdir -p "$w/local-reviews/$(printf 'b%.0s' $(seq 40))"
        echo new >"$w/local-reviews/$(printf 'b%.0s' $(seq 40))/report"
        touch -t "$OLD" "$w/local-reviews/$(printf 'b%.0s' $(seq 40))"
    }
    run() { PATH="$stub:$PATH" STUB_GH_HEADS="$tmp/heads" bash "$script" "$@"; }

    # 1. A real run.
    ws="$tmp/ws1"; make_ws "$ws"
    out="$(run "$ws" 2>&1)" && rc=0 || rc=$?
    check "a run exits 0" [ "$rc" = 0 ]
    for f in pr-body-x.md commit-x.txt merge-check-1.md review-msg-x.txt gate-x.log; do
        check "old $f deleted" gone "$ws/$f"
    done
    for f in pr-body-fresh.md commit-fresh.txt merge-check-fresh.md review-msg-fresh.txt gate-fresh.log; do
        check "fresh $f kept" there "$ws/$f"
    done
    for f in TrailMetrics start-agent.sh main-ci-ack hook-debug queue/queue.tsv; do check "protected $f kept" there "$ws/$f"; done
    check "the repo inside is untouched" [ -d "$ws/TrailMetrics/.git" ]
    check "unknown notes.md kept" there "$ws/notes.md"
    check "gate-x.txt (not .log) kept" there "$ws/gate-x.txt"
    check "unknown printed" grep -qxF "kept, unknown: notes.md" <<<"$out"
    check "symlink untouched" [ -L "$ws/pr-body-link.md" ]
    check "symlink target untouched" there "$tmp/target"
    check "symlink printed as unknown" grep -qxF "kept, unknown: pr-body-link.md" <<<"$out"
    check "deleted line printed" grep -qxF "deleted commit-x.txt" <<<"$out"
    check "old record of a merged SHA deleted" gone "$ws/local-reviews/$sha_merged"
    check "old record of no branch and no PR deleted" gone "$ws/local-reviews/$sha_old"
    check "record of an open-PR head kept" there "$ws/local-reviews/$sha_open"
    check "record of an unmerged local branch head kept" there "$ws/local-reviews/$sha_branch"
    check "record with a fresh file kept" there "$ws/local-reviews/$(printf 'b%.0s' $(seq 40))"
    check "summary counts" grep -qxF "clean-agent-workspace: removed 5 files, 2 review records; kept 8 fresh or in use, 3 unknown" <<<"$out"
    out="$(run "$ws" 2>&1)" && rc=0 || rc=$?
    check "a second run removes nothing" grep -qxF "clean-agent-workspace: removed 0 files, 0 review records; kept 8 fresh or in use, 3 unknown" <<<"$out"

    # 2. --dry-run deletes nothing.
    ws="$tmp/ws2"; make_ws "$ws"
    out="$(run --dry-run "$ws" 2>&1)" && rc=0 || rc=$?
    check "--dry-run exits 0" [ "$rc" = 0 ]
    check "--dry-run keeps old files" there "$ws/pr-body-x.md"
    check "--dry-run keeps old records" there "$ws/local-reviews/$sha_old"
    check "--dry-run prints would delete" grep -qxF "would delete gate-x.log" <<<"$out"
    check "--dry-run summary" grep -qxF "clean-agent-workspace: would remove 5 files, 2 review records; kept 8 fresh or in use, 3 unknown" <<<"$out"

    # 3. A gh failure keeps every record (old files still go).
    ws="$tmp/ws3"; make_ws "$ws"
    out="$(STUB_GH_FAIL=1 run "$ws" 2>&1)" && rc=0 || rc=$?
    check "gh failure: exits 0" [ "$rc" = 0 ]
    check "gh failure: old record kept" there "$ws/local-reviews/$sha_old"
    check "gh failure: merged record kept" there "$ws/local-reviews/$sha_merged"
    check "gh failure: said so" grep -q "no review record deleted" <<<"$out"
    check "gh failure: old files still deleted" gone "$ws/commit-x.txt"

    # 4. gh output that is not a list of SHAs counts as a failure.
    ws="$tmp/ws4"; make_ws "$ws"
    echo "not a sha" >"$tmp/heads"
    run "$ws" >/dev/null 2>&1 || true
    check "bad gh output: old record kept" there "$ws/local-reviews/$sha_old"

    # 4b. A git failure (no origin/main) keeps every record too.
    ws="$tmp/ws4b"; make_ws "$ws"
    git -C "$ws/TrailMetrics" update-ref -d refs/remotes/origin/main
    out="$(run "$ws" 2>&1)" && rc=0 || rc=$?
    check "no origin/main: exits 0" [ "$rc" = 0 ]
    check "no origin/main: old record kept" there "$ws/local-reviews/$sha_old"
    check "no origin/main: said so" grep -q "no review record deleted" <<<"$out"

    # 6. The queue/ folder: task texts of finished entries only, old log lines only.
    local now_stamp qline qdir
    now_stamp="$(date +%Y-%m-%dT%H:%M:%S)"
    qline() { printf '%s\t%s\tchore/%s\t-\tagent\t%s\t-\n' "$1" "$2" "$2" "$3" >>"$ws/queue/queue.tsv"; }
    make_queue_ws() { # make_queue_ws <dir>: open and finished entries with old texts, two logs with old and new lines
        local w="$1" s
        make_ws "$w"
        ws="$w"; qdir="$w/queue"
        mkdir -p "$qdir/tasks" "$qdir/subagent" "$qdir/locks"
        : >"$qdir/queue.tsv"
        qline 1 open-planned planned; qline 2 open-building building; qline 3 open-ready ready; qline 4 open-pushed pushed
        qline 5 done-merged merged; qline 6 done-dropped dropped; qline 7 merged-fresh merged
        for s in open-planned open-building open-ready open-pushed done-merged done-dropped orphan-text; do
            echo "text of $s" >"$qdir/tasks/$s.md"; touch -t "$OLD" "$qdir/tasks/$s.md"
        done
        echo "text of merged-fresh" >"$qdir/tasks/merged-fresh.md"
        echo x >"$tmp/linktarget"; ln -s "$tmp/linktarget" "$qdir/tasks/open-link.md"
        echo x >"$qdir/tasks/Bad_Name.md"; touch -t "$OLD" "$qdir/tasks/Bad_Name.md"
        printf '2000-01-01T00:00:00\told1\n2000-01-02T00:00:00\told2\n%s\tnew1\nno timestamp here\n' "$now_stamp" >"$qdir/subagent/guard.log"
        printf '2000-01-01T00:00:00\tpid\twait\tx\tcmd\n%s\tpid\tstart\t0s\tcmd\n' "$now_stamp" >"$qdir/locks/heavy-run.log"
        touch -t "$OLD" "$qdir/queue.tsv" "$qdir/locks"
    }
    make_queue_ws "$tmp/ws6"
    out="$(run "$ws" 2>&1)" && rc=0 || rc=$?
    check "queue: a run exits 0" [ "$rc" = 0 ]
    for f in open-planned open-building open-ready open-pushed; do
        check "queue: the old text of the open entry $f is kept" there "$qdir/tasks/$f.md"
    done
    check "queue: the old text of a merged entry is deleted" gone "$qdir/tasks/done-merged.md"
    check "queue: the old text of a dropped entry is deleted" gone "$qdir/tasks/done-dropped.md"
    check "queue: the fresh text of a merged entry is kept" there "$qdir/tasks/merged-fresh.md"
    check "queue: a text with no row is kept" there "$qdir/tasks/orphan-text.md"
    check "queue: a text with no row is printed as unknown" grep -qxF "kept, unknown: queue/tasks/orphan-text.md" <<<"$out"
    check "queue: a link in tasks/ is kept" [ -L "$qdir/tasks/open-link.md" ]
    check "queue: a link's target is kept" there "$tmp/linktarget"
    check "queue: a file that is not a slug.md is kept" there "$qdir/tasks/Bad_Name.md"
    check "queue: the deleted text is printed" grep -qxF "deleted queue/tasks/done-merged.md" <<<"$out"
    check "queue: the queue file is kept" there "$qdir/queue.tsv"
    check "queue: the old guard log lines are gone" bash -c "! grep -q 'old1' '$qdir/subagent/guard.log' && ! grep -q 'old2' '$qdir/subagent/guard.log'"
    check "queue: the new guard log line is kept" grep -q 'new1' "$qdir/subagent/guard.log"
    check "queue: a guard log line without a timestamp is kept" grep -q 'no timestamp here' "$qdir/subagent/guard.log"
    check "queue: the old heavy-run log line is gone" bash -c "! grep -q 'wait' '$qdir/locks/heavy-run.log'"
    check "queue: the new heavy-run log line is kept" grep -q 'start' "$qdir/locks/heavy-run.log"
    check "queue: the trim is printed" grep -qxF "trimmed queue/subagent/guard.log: removed 2 lines older than 3 days" <<<"$out"
    check "queue: the folder and its locks dir are kept" bash -c "[ -d '$qdir' ] && [ -d '$qdir/locks' ]"
    out="$(run "$ws" 2>&1)"
    check "queue: a second run deletes and trims nothing" bash -c "! grep -q '^deleted queue/\|^trimmed' <<<'$out'"
    # A log with nothing old is not rewritten (its modification time stays).
    printf '%s\tnew\n' "$now_stamp" >"$qdir/subagent/guard.log"; touch -t "$OLD" "$qdir/subagent/guard.log"
    run "$ws" >/dev/null 2>&1
    check "queue: a log with nothing old is not touched" [ "$(mtime_of "$qdir/subagent/guard.log")" = "$(mtime_of "$qdir/queue.tsv")" ]

    # A log that cannot be read is reported (exit 1), not skipped silently.
    make_queue_ws "$tmp/ws6u"
    chmod 000 "$qdir/subagent/guard.log"
    out="$(run "$ws" 2>&1)" && rc=0 || rc=$?
    chmod 600 "$qdir/subagent/guard.log"
    check "queue: an unreadable log exits 1" [ "$rc" = 1 ]
    check "queue: an unreadable log is reported" grep -q "could not read queue/subagent/guard.log; it is not trimmed" <<<"$out"
    check "queue: the other log is still trimmed" grep -qxF "trimmed queue/locks/heavy-run.log: removed 1 lines older than 3 days" <<<"$out"
    check "queue: the texts are still cleaned" gone "$qdir/tasks/done-merged.md"

    # --dry-run deletes and trims nothing, and says what it would.
    make_queue_ws "$tmp/ws6d"
    out="$(run --dry-run "$ws" 2>&1)" && rc=0 || rc=$?
    check "queue: --dry-run exits 0" [ "$rc" = 0 ]
    check "queue: --dry-run keeps the finished text" there "$qdir/tasks/done-merged.md"
    check "queue: --dry-run keeps the old log lines" grep -q 'old1' "$qdir/subagent/guard.log"
    check "queue: --dry-run says what it would delete" grep -qxF "would delete queue/tasks/done-merged.md" <<<"$out"
    check "queue: --dry-run says what it would trim" grep -qxF "would trim queue/subagent/guard.log: removed 2 lines older than 3 days" <<<"$out"

    # No text is deleted when the queue file cannot be read as a queue.
    for bad in malformed missing link badstatus; do
        make_queue_ws "$tmp/ws6-$bad"
        case "$bad" in
            malformed) printf 'this is not a queue\n' >"$qdir/queue.tsv" ;;
            missing) rm -f "$qdir/queue.tsv" ;;
            link) mv "$qdir/queue.tsv" "$tmp/real-queue-$bad.tsv"; ln -s "$tmp/real-queue-$bad.tsv" "$qdir/queue.tsv" ;;
            badstatus) qline 8 odd-one finished ;;
        esac
        out="$(run "$ws" 2>&1)" && rc=0 || rc=$?
        check "queue: $bad queue file: exits 0" [ "$rc" = 0 ]
        check "queue: $bad queue file: the finished text is kept" there "$qdir/tasks/done-merged.md"
        check "queue: $bad queue file: every open text is kept" bash -c "[ -e '$qdir/tasks/open-planned.md' ] && [ -e '$qdir/tasks/open-pushed.md' ]"
        check "queue: $bad queue file: said so" grep -q "no task text deleted" <<<"$out"
    done

    # With the real queue.sh: an entry's text survives while the entry is open and goes once it is finished and old.
    local qsh rq
    qsh="$(cd "$(dirname "$script")/../queue" && pwd)/queue.sh"
    if [ -f "$qsh" ]; then
        make_ws "$tmp/ws7"; ws="$tmp/ws7"; rq="$ws/queue/queue.tsv"
        rm -f "$rq"; printf 'Task text.\n' >"$tmp/t.txt"
        for f in one two three; do QUEUE_FILE="$rq" bash "$qsh" add "$f" --branch "chore/$f" --task "$tmp/t.txt" >/dev/null; done
        touch -t "$OLD" "$ws/queue/tasks/one.md" "$ws/queue/tasks/two.md" "$ws/queue/tasks/three.md"
        run "$ws" >/dev/null 2>&1
        check "queue.sh: the old texts of three open entries are kept" bash -c "[ -e '$ws/queue/tasks/one.md' ] && [ -e '$ws/queue/tasks/two.md' ] && [ -e '$ws/queue/tasks/three.md' ]"
        QUEUE_FILE="$rq" bash "$qsh" set one status=dropped >/dev/null
        run "$ws" >/dev/null 2>&1
        check "queue.sh: the text of the entry dropped since is deleted" gone "$ws/queue/tasks/one.md"
        check "queue.sh: the texts of the entries still open are kept" bash -c "[ -e '$ws/queue/tasks/two.md' ] && [ -e '$ws/queue/tasks/three.md' ]"
        QUEUE_FILE="$rq" bash "$qsh" task two >/dev/null && echo "ok   queue.sh: task prints the text that is kept" || { echo "FAIL queue.sh: task of a kept text" >&2; fails=$((fails + 1)); }
    fi

    # 5. The guard refuses a wrong dir.
    mkdir -p "$tmp/wrong/TrailMetrics"
    echo old >"$tmp/wrong/pr-body-x.md"; touch -t "$OLD" "$tmp/wrong/pr-body-x.md"
    out="$(run "$tmp/wrong" 2>&1)" && rc=0 || rc=$?
    check "guard: no start-agent.sh exits 2" [ "$rc" = 2 ]
    check "guard: nothing deleted" there "$tmp/wrong/pr-body-x.md"
    rm -rf "$tmp/wrong/TrailMetrics"; echo x >"$tmp/wrong/start-agent.sh"
    run "$tmp/wrong" >/dev/null 2>&1 && rc=0 || rc=$?
    check "guard: no TrailMetrics/ exits 2" [ "$rc" = 2 ]
    run --bogus >/dev/null 2>&1 && rc=0 || rc=$?
    check "unknown option exits 2" [ "$rc" = 2 ]

    if [ "$fails" -ne 0 ]; then
        echo "clean-agent-workspace.sh self-test: $fails failed" >&2
        return 1
    fi
    echo "clean-agent-workspace.sh self-test: all passed"
}

DRY_RUN=0
WS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --self-test) self_test; exit $? ;;
        --dry-run) DRY_RUN=1 ;;
        -*) echo "usage: $0 [--dry-run] [<workspace dir>] | --self-test" >&2; exit 2 ;;
        *) [ -z "$WS" ] || { echo "usage: $0 [--dry-run] [<workspace dir>] | --self-test" >&2; exit 2; }; WS="$1" ;;
    esac
    shift
done
WS="${WS:-$HOME/agent-workspace}"
WS="${WS%/}"
rc=0
clean || rc=$?
exit "$rc"
