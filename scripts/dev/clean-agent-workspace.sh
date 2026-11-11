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
#   hook-debug/ (kept to its newest 10 files by scripts/claude-hooks/require-local-review.sh).
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
# `kept, unknown: <name>` per unknown entry, then one summary line:
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
    for e in "$WS"/* "$WS"/.[!.]*; do
        [ -e "$e" ] || [ -L "$e" ] || continue
        name="${e##*/}"
        if [ ! -L "$e" ]; then
            case "$name" in
                TrailMetrics | start-agent.sh | main-ci-ack | hook-debug) continue ;;
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
        mkdir -p "$w/TrailMetrics" "$w/hook-debug" "$w/local-reviews"
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
    for f in TrailMetrics start-agent.sh main-ci-ack hook-debug; do check "protected $f kept" there "$ws/$f"; done
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
