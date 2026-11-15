#!/usr/bin/env bash
# Deletes the agent workspace's files of finished work, whatever their names: PR description drafts,
# commit messages, merge-check comments, reviewer messages, gate and CI logs, scratch scripts and
# diffs, and old review records. Run at the start of every task (tm-agent-loop, "Preconditions") and
# by `scripts/queue/queue.sh set` whenever an entry becomes merged or dropped, so a long queue session
# cleans as it goes. What is in use is never deleted (see "A loose file"), which makes a run safe at
# any time; only the rewrite of the two logs under queue/ is not (see below).
#
# Usage:
#   scripts/dev/clean-agent-workspace.sh [--dry-run] [<workspace dir>]   (default ~/agent-workspace)
#   scripts/dev/clean-agent-workspace.sh --self-test
#
# Guard: refuses (exit 2) unless <workspace dir> holds the directory `TrailMetrics/` and the file
# `start-agent.sh`. Only the entries directly inside the dir are looked at, symlinks are never
# followed or deleted, and `TrailMetrics/` is never entered.
#
# A loose file (a regular file directly in the dir) is deleted when ALL of these hold:
#   - it is not state: never `start-agent.sh`, `main-ci-ack` (state of scripts/main-ci-status.sh
#     --ack), `auto-mode-defaults.json`, a name starting with `keep-` (the way to keep a file of any
#     name), nor a file with a configuration or secret extension (.json .plist .xcconfig .properties
#     .env .pem .key: kept and printed as unknown);
#   - it is older than 3 days (modification time);
#   - it is not in use by an open entry of the PR queue. In use means any of: (a) it is newer than
#     the oldest open entry's task text (`queue/tasks/<slug>.md`, written when the entry was added), so
#     whatever was made since an open entry was queued stays until that entry is merged or dropped;
#     (b) its name contains the slug of an open entry; (c) its name contains the PR number of an open
#     entry as a number of its own (`mc-293.md`, `pr-293`). When the queue cannot be read (`queue/`
#     exists but its queue file is missing, a link or not a well-formed queue) or an open entry has no
#     task text, no loose file is deleted at all: what is in use cannot be known. With no `queue/`
#     folder only the state and age rules apply.
# The name does not matter: `mc-*.md`, `t-push-*`, `edit-*.py`, `*.diff`, `ios3-*.log`, `spike-*` and
# the drafts, commit messages and gate logs are all loose files. A hidden entry, a symlink and a
# directory other than the ones named below are never deleted and are printed as unknown.
#
# Always kept: TrailMetrics/, hook-debug/ (kept to its newest 10 files by
#   scripts/claude-hooks/require-local-review.sh), queue/ itself, its queue file (queue.tsv, which
#   `add` and `set` use for the slugs and the order), its lock files and the folder structure; what is
#   cleaned inside it is listed next, and the review records below.
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
#     safe against a writer at the same moment: a line appended while it runs may be lost, and a log
#     is not a decision input.
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

# The PR queue's state, read once per run (see "A loose file" in the header). QUEUE_STATE is `none` (no
# queue/ folder), `ok`, or `bad` (queue/ exists and its queue file cannot be read as a queue, or an open
# entry has no task text, so what is in use cannot be known). OPEN_FLOOR is the modification time of the
# oldest open entry's task text; OPEN_SLUGS and OPEN_PRS list the open entries' slugs and PR numbers.
load_queue_state() {
    local q="$WS/queue" qf="$WS/queue/queue.tsv" slug pr st m
    QUEUE_STATE=none OPEN_FLOOR=99999999999 OPEN_SLUGS="" OPEN_PRS=""
    { [ -d "$q" ] && [ ! -L "$q" ]; } || return 0
    QUEUE_STATE=bad
    queue_file_ok "$qf" || return 0
    while IFS=$'\t' read -r _ slug _ _ _ st pr; do
        case "$st" in merged | dropped) continue ;; esac
        { [ -f "$q/tasks/$slug.md" ] && [ ! -L "$q/tasks/$slug.md" ]; } || return 0
        m="$(mtime_of "$q/tasks/$slug.md")" || return 0
        [ "$m" -ge "$OPEN_FLOOR" ] || OPEN_FLOOR="$m"
        OPEN_SLUGS="$OPEN_SLUGS $slug"
        [ "$pr" = - ] || OPEN_PRS="$OPEN_PRS $pr"
    done < <(awk -F '\t' '!/^#/ && NF == 7' "$qf")
    QUEUE_STATE=ok
}

file_in_use() { # file_in_use <name> <path>: used by an open entry of the queue (or not knowable)
    local name="$1" e="$2" m slug pr
    [ "$QUEUE_STATE" = bad ] && return 0
    [ "$QUEUE_STATE" = none ] && return 1
    m="$(mtime_of "$e")" || return 0
    [ "$m" -ge "$OPEN_FLOOR" ] && return 0
    for slug in $OPEN_SLUGS; do
        case "$name" in *"$slug"*) return 0 ;; esac
    done
    for pr in $OPEN_PRS; do
        [[ "$name" =~ (^|[^0-9])${pr}([^0-9]|$) ]] && return 0
    done
    return 1
}

clean_loose_file() { # clean_loose_file <path> <name>: a loose regular file of the workspace, whatever its name
    if is_old "$1" && ! file_in_use "$2" "$1"; then remove "$1" "$2" file; else FRESH=$((FRESH + 1)); fi
}

clean() {
    local e name
    if [ ! -d "$WS/TrailMetrics" ] || [ -L "$WS/TrailMetrics" ] || [ ! -f "$WS/start-agent.sh" ] || [ -L "$WS/start-agent.sh" ]; then
        echo "clean-agent-workspace: refused: $WS does not hold TrailMetrics/ and start-agent.sh" >&2
        return 2
    fi
    NOW="$(date +%s)" FILES=0 RECORDS=0 FRESH=0 UNKNOWN=0 FAILED=0
    CUTOFF="$(time_string $((NOW - MAX_AGE_SECONDS)))"
    load_queue_state
    if [ "$QUEUE_STATE" = bad ]; then
        echo "clean-agent-workspace: the queue could not be read, or an open entry has no task text; no loose file deleted" >&2
    fi
    for e in "$WS"/* "$WS"/.[!.]*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        name="${e##*/}"
        if [ ! -L "$e" ]; then
            case "$name" in
                TrailMetrics | hook-debug) continue ;;
                queue) clean_queue "$e"; continue ;;
                local-reviews) if [ -d "$e" ]; then clean_records "$e"; continue; fi ;;
                start-agent.sh | main-ci-ack | auto-mode-defaults.json | keep-*) continue ;;
                .* | *.json | *.plist | *.xcconfig | *.properties | *.env | *.pem | *.key) ;;
                *) if [ -f "$e" ]; then clean_loose_file "$e" "$name"; continue; fi ;;
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
        : >"$w/queue/queue.tsv"; touch -t "$OLD" "$w/queue/queue.tsv" "$w/queue"   # a well-formed queue with no entry
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
    check "any name: the old notes.md is deleted" gone "$ws/notes.md"
    check "any name: the old gate-x.txt (not .log) is deleted" gone "$ws/gate-x.txt"
    check "symlink untouched" [ -L "$ws/pr-body-link.md" ]
    check "symlink target untouched" there "$tmp/target"
    check "symlink printed as unknown" grep -qxF "kept, unknown: pr-body-link.md" <<<"$out"
    check "deleted line printed" grep -qxF "deleted commit-x.txt" <<<"$out"
    check "old record of a merged SHA deleted" gone "$ws/local-reviews/$sha_merged"
    check "old record of no branch and no PR deleted" gone "$ws/local-reviews/$sha_old"
    check "record of an open-PR head kept" there "$ws/local-reviews/$sha_open"
    check "record of an unmerged local branch head kept" there "$ws/local-reviews/$sha_branch"
    check "record with a fresh file kept" there "$ws/local-reviews/$(printf 'b%.0s' $(seq 40))"
    check "summary counts" grep -qxF "clean-agent-workspace: removed 7 files, 2 review records; kept 8 fresh or in use, 1 unknown" <<<"$out"
    out="$(run "$ws" 2>&1)" && rc=0 || rc=$?
    check "a second run removes nothing" grep -qxF "clean-agent-workspace: removed 0 files, 0 review records; kept 8 fresh or in use, 1 unknown" <<<"$out"

    # 2. --dry-run deletes nothing.
    ws="$tmp/ws2"; make_ws "$ws"
    out="$(run --dry-run "$ws" 2>&1)" && rc=0 || rc=$?
    check "--dry-run exits 0" [ "$rc" = 0 ]
    check "--dry-run keeps old files" there "$ws/pr-body-x.md"
    check "--dry-run keeps old records" there "$ws/local-reviews/$sha_old"
    check "--dry-run prints would delete" grep -qxF "would delete gate-x.log" <<<"$out"
    check "--dry-run summary" grep -qxF "clean-agent-workspace: would remove 7 files, 2 review records; kept 8 fresh or in use, 1 unknown" <<<"$out"

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

    # 7. A loose file of any name is cleaned; state and what an open entry uses are not.
    local fresh_names old_names d7
    ago() { # ago <days> <path>: the modification time <days> days ago
        local t=$(($(date +%s) - $1 * 86400))
        if date -d @0 >/dev/null 2>&1; then touch -d "@$t" "$2"; else touch -t "$(date -r "$t" +%Y%m%d%H%M.%S)" "$2"; fi
    }
    scratch_names="mc-264.md t-push-1.txt t-merge-1.txt edit-x.py make-x.py a.diff ios3-270.log ui-full-local.log spike-gate-a.log spike-t0 close-277.md scratch"
    make_loose_ws() { # make_loose_ws <dir> [no-queue]: scratch files 5 days and 1 day old, state files 40 days old
        local w="$1" n
        mkdir -p "$w/TrailMetrics"
        echo '#!/bin/sh' >"$w/start-agent.sh"; echo 1 >"$w/main-ci-ack"; echo '{}' >"$w/auto-mode-defaults.json"
        echo k >"$w/keep-notes.txt"; echo '{}' >"$w/other.json"; echo h >"$w/.hidden"; mkdir "$w/somedir"
        echo x >"$tmp/loose-target"; ln -s "$tmp/loose-target" "$w/linked.md"
        for n in start-agent.sh main-ci-ack auto-mode-defaults.json keep-notes.txt other.json .hidden; do ago 40 "$w/$n"; done
        for n in $scratch_names; do echo old >"$w/$n"; ago 5 "$w/$n"; echo new >"$w/fresh-$n"; ago 1 "$w/fresh-$n"; done
        echo 'odd' >"$w/Weird Name (1).txt"; ago 5 "$w/Weird Name (1).txt"
        if [ "${2:-}" != no-queue ]; then mkdir -p "$w/queue"; : >"$w/queue/queue.tsv"; fi
    }
    d7="$tmp/ws7a"; make_loose_ws "$d7"
    out="$(run "$d7" 2>&1)" && rc=0 || rc=$?
    check "loose: a run exits 0" [ "$rc" = 0 ]
    for f in $scratch_names "Weird Name (1).txt"; do check "loose: the old '$f' is deleted, whatever its name" gone "$d7/$f"; done
    for f in $scratch_names; do check "loose: the fresh '$f' is kept" there "$d7/fresh-$f"; done
    for f in start-agent.sh main-ci-ack auto-mode-defaults.json keep-notes.txt other.json .hidden somedir; do
        check "loose: '$f' is kept (state, keep-, configuration extension, hidden, directory)" there "$d7/$f"
    done
    check "loose: a symlink is kept" [ -L "$d7/linked.md" ]
    check "loose: its target is kept" there "$tmp/loose-target"
    check "loose: other.json, .hidden and somedir are printed as unknown" bash -c "grep -qxF 'kept, unknown: other.json' <<<'$out' && grep -qxF 'kept, unknown: .hidden' <<<'$out' && grep -qxF 'kept, unknown: somedir' <<<'$out'"
    check "loose: the state files are not printed" bash -c "! grep -q 'start-agent.sh\|main-ci-ack\|auto-mode-defaults\|keep-notes' <<<'$out'"
    d7="$tmp/ws7n"; make_loose_ws "$d7" no-queue
    run "$d7" >/dev/null 2>&1
    check "loose: with no queue/ folder the age rule applies: old deleted" gone "$d7/mc-264.md"
    check "loose: with no queue/ folder the fresh file is kept" there "$d7/fresh-mc-264.md"
    check "loose: with no queue/ folder the state is kept" bash -c "[ -e '$d7/start-agent.sh' ] && [ -e '$d7/auto-mode-defaults.json' ]"
    d7="$tmp/ws7d"; make_loose_ws "$d7"
    out="$(run --dry-run "$d7" 2>&1)"
    check "loose: --dry-run deletes nothing" there "$d7/mc-264.md"
    check "loose: --dry-run says what it would delete" grep -qxF "would delete mc-264.md" <<<"$out"

    # What an open entry uses is kept: newer than its task text, its slug or PR number in the name.
    qrow() { printf '%s\t%s\tchore/%s\t-\tagent\t%s\t%s\n' "$1" "$2" "$2" "$3" "$4" >>"$d7/queue/queue.tsv"; }
    d7="$tmp/ws7o"; make_loose_ws "$d7"
    mkdir -p "$d7/queue/tasks"
    qrow 1 open-one pushed 293; qrow 2 open-two planned -; qrow 3 done-entry merged 12
    echo t >"$d7/queue/tasks/open-one.md"; ago 5 "$d7/queue/tasks/open-one.md"
    echo t >"$d7/queue/tasks/open-two.md"; ago 4 "$d7/queue/tasks/open-two.md"
    for f in older-than-the-entry.md mid-session.md x-open-one-y.log mc-293.md mc-2930.md pr-293-x.md two-open-two.txt done-entry.md; do echo x >"$d7/$f"; done
    ago 8 "$d7/older-than-the-entry.md"; ago 4 "$d7/mid-session.md"; ago 9 "$d7/x-open-one-y.log"; ago 9 "$d7/mc-293.md"
    ago 9 "$d7/mc-2930.md"; ago 9 "$d7/pr-293-x.md"; ago 9 "$d7/two-open-two.txt"; ago 9 "$d7/done-entry.md"
    out="$(run "$d7" 2>&1)" && rc=0 || rc=$?
    check "in use: a run exits 0" [ "$rc" = 0 ]
    check "in use: a file older than the oldest open entry is deleted" gone "$d7/older-than-the-entry.md"
    check "in use: a file of a finished entry's name and age is deleted" gone "$d7/done-entry.md"
    check "in use: a file whose number only contains the PR number is deleted" gone "$d7/mc-2930.md"
    check "in use: a file newer than the oldest open entry's text is kept" there "$d7/mid-session.md"
    check "in use: a file named for an open entry's slug is kept" there "$d7/x-open-one-y.log"
    check "in use: a second open slug is kept" there "$d7/two-open-two.txt"
    check "in use: a file named for an open entry's PR number is kept" there "$d7/mc-293.md"
    check "in use: pr-293-x.md is kept" there "$d7/pr-293-x.md"
    check "in use: the open entries' task texts are kept" bash -c "[ -e '$d7/queue/tasks/open-one.md' ] && [ -e '$d7/queue/tasks/open-two.md' ]"
    check "in use: the state files are kept" bash -c "[ -e '$d7/start-agent.sh' ] && [ -e '$d7/main-ci-ack' ]"
    # Once the entries are finished the same files go.
    printf '1\topen-one\tchore/open-one\t-\tagent\tmerged\t293\n2\topen-two\tchore/open-two\t-\tagent\tdropped\t-\n3\tdone-entry\tchore/done-entry\t-\tagent\tmerged\t12\n' >"$d7/queue/queue.tsv"
    run "$d7" >/dev/null 2>&1
    check "in use: after the entries finish, the file named for a slug goes" gone "$d7/x-open-one-y.log"
    check "in use: after the entries finish, the mid-session file goes" gone "$d7/mid-session.md"
    check "in use: after the entries finish, the file named for the PR goes" gone "$d7/mc-293.md"
    check "in use: after the entries finish, the fresh file is still kept" there "$d7/fresh-mc-264.md"

    # When what is in use cannot be known, no loose file is deleted.
    for bad in no-text malformed missing link; do
        d7="$tmp/ws7-$bad"; make_loose_ws "$d7"; mkdir -p "$d7/queue/tasks"
        case "$bad" in
            no-text) qrow 1 open-one planned - ;;
            malformed) printf 'not a queue\n' >"$d7/queue/queue.tsv" ;;
            missing) rm -f "$d7/queue/queue.tsv" ;;
            link) rm -f "$d7/queue/queue.tsv"; echo x >"$tmp/q-$bad"; ln -s "$tmp/q-$bad" "$d7/queue/queue.tsv" ;;
        esac
        out="$(run "$d7" 2>&1)" && rc=0 || rc=$?
        check "unknown queue ($bad): exits 0" [ "$rc" = 0 ]
        check "unknown queue ($bad): the old loose files are kept" bash -c "[ -e '$d7/mc-264.md' ] && [ -e '$d7/scratch' ] && [ -e '$d7/Weird Name (1).txt' ]"
        check "unknown queue ($bad): said so" grep -q "no loose file deleted" <<<"$out"
    done

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
