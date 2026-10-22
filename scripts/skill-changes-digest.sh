#!/usr/bin/env bash
# Skill changes digest: what changed in the skills and CLAUDE.md files on main since a date, so the
# human can see after the fact what agents changed in the reference skills (which they may edit
# without his review) and revert anything (docs/epics/protected-paths-review.md, Decision 6).
#
#   scripts/skill-changes-digest.sh [--since YYYY-MM-DD]   default: the last 7 days
#   scripts/skill-changes-digest.sh --self-test            run the cases below; exit 0 = all ok
#
# Read-only, git only, no network: it reads origin/main as it is in this clone, so run
# `git fetch origin` first for an up-to-date digest. It never writes anything.
#
# Output: for every commit of the first-parent history of origin/main since DATE (committer date,
# from 00:00 local time) that touched .claude/skills/ or any CLAUDE.md, oldest first, one line
# `<short hash> <date> <subject>` (the subject of a squash-merged PR is its title with `(#N)`),
# then, indented, each changed file of those paths and its `+` and `-` lines (no context), then a
# final line with the number of commits. Without such commits, the single line
# `no changes to skills or CLAUDE.md since DATE`. Exit 0; a bad date or an unknown option prints
# the usage on stderr and exits 2; a git error exits 2.
# Runs on bash 3.2 (macOS) and GNU or BSD date.
#
# --self-test builds a scratch git repository (fixed dates, TZ=UTC, an `origin/main` ref made with
# update-ref) holding a root commit, a commit outside the watched paths, a side branch merged with
# a merge commit, and a commit that edits skill and CLAUDE.md files. It runs a copy of this script
# there and compares stdout with scripts/skill-changes-digest-fixtures/*.stdout (short hashes
# replaced by HASH), plus the no-changes line, exit 2 with the usage for a bad date or an unknown
# option, and exit 2 without `origin/main`. SKILL_CHANGES_DIGEST_SCRIPT=<file> runs the cases
# against another copy of the script (to show them going red on a broken one).
set -uo pipefail

usage() {
    echo "usage: scripts/skill-changes-digest.sh [--since YYYY-MM-DD]" >&2
    exit 2
}

# Strict YYYY-MM-DD that names a real calendar day.
valid_date() {
    local y m d max
    case "$1" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) return 1 ;;
    esac
    y=$((10#${1:0:4})); m=$((10#${1:5:2})); d=$((10#${1:8:2}))
    case $m in
        1|3|5|7|8|10|12) max=31 ;;
        4|6|9|11) max=30 ;;
        2) if (( (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 )); then max=29; else max=28; fi ;;
        *) return 1 ;;
    esac
    [ "$d" -ge 1 ] && [ "$d" -le "$max" ]
}

# --- self-test ---------------------------------------------------------------------------------

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Removes a scratch directory. Only a failure that leaves files behind (something may still be
# writing into it) is retried, after 0.2 seconds, up to 5 attempts; then it names what is left.
remove_scratch() {
    local dir="$1" attempt=0
    while [ "$attempt" -lt 5 ]; do
        [ "$attempt" -eq 0 ] || sleep 0.2
        rm -rf "$dir" 2>/dev/null
        [ -e "$dir" ] || return 0
        attempt=$((attempt + 1))
    done
    echo "cannot remove $dir after 5 attempts; left: $(cd "$dir" && find . | head -50 | tr '\n' ' ')" >&2
    return 1
}

self_test() {
    local fixtures failed=0 under_test="${SKILL_CHANGES_DIGEST_SCRIPT:-$SELF}"
    fixtures="$(dirname "$SELF")/skill-changes-digest-fixtures"
    work="$(mktemp -d)" || return 2   # global: the EXIT trap runs after this function returns
    trap 'remove_scratch "$work" || exit 1' EXIT
    export TZ=UTC GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1

    # g <date> <git args...>: git in the scratch repository, committing at <date> (12:00 UTC)
    local repo="$work/repo"
    g() {
        local day="$1"; shift
        GIT_AUTHOR_DATE="${day}T12:00:00+0000" GIT_COMMITTER_DATE="${day}T12:00:00+0000" \
            git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.com \
            -c commit.gpgsign=false -c core.hooksPath=/dev/null -c gc.auto=0 -c maintenance.auto=false "$@"
    }
    # put <relative path> <line>: replaces the file's content with one line
    put() { mkdir -p "$repo/$(dirname "$1")" && printf '%s\n' "$2" > "$repo/$1"; }

    mkdir -p "$repo/scripts" && cp "$under_test" "$repo/scripts/skill-changes-digest.sh" || return 2
    git -C "$repo" init -q || return 2
    # 2026-01-10 root commit: skill file (watched) and a source file
    put .claude/skills/a/SKILL.md "alpha"
    put src/x.txt "one"
    g 2026-01-10 add -A && g 2026-01-10 commit -q -m "chore(skills): add skill a" || return 2
    # 2026-01-12 outside the watched paths (README, NOTCLAUDE.md does not match **/CLAUDE.md)
    put README.md "readme"
    put docs/NOTCLAUDE.md "not watched"
    g 2026-01-12 add -A && g 2026-01-12 commit -q -m "docs: readme" || return 2
    # side branch (2026-01-14) merged with a merge commit (2026-01-15); only the merge is first-parent
    g 2026-01-14 checkout -q -b side || return 2
    put .claude/skills/b/SKILL.md "bravo"
    g 2026-01-14 add -A && g 2026-01-14 commit -q -m "chore(skills): add skill b" || return 2
    g 2026-01-15 checkout -q - || return 2
    g 2026-01-15 merge -q --no-ff -m "chore(skills): merge skill b (#7)" side || return 2
    # 2026-01-20 edits a skill (one line replaced, one added), adds both kinds of CLAUDE.md
    put .claude/skills/a/SKILL.md "alpha two"
    printf 'extra\n' >> "$repo/.claude/skills/a/SKILL.md"
    put CLAUDE.md "root"
    put androidApp/CLAUDE.md "android"
    put src/x.txt "two"
    g 2026-01-20 add -A && g 2026-01-20 commit -q -m "docs: update skills and CLAUDE.md" || return 2
    g 2026-01-20 update-ref refs/remotes/origin/main HEAD || return 2

    # run_digest <args...>: sets OUT, ERR and CODE
    run_digest() {
        (cd "$repo" && scripts/skill-changes-digest.sh "$@" >"$work/stdout" 2>"$work/stderr")
        CODE=$?
        OUT="$(sed -E 's/^[0-9a-f]{7,} /HASH /' "$work/stdout")"
        ERR="$(cat "$work/stderr")"
    }
    check() { # <label> <ok: 0 or 1>
        if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; failed=1; fi
    }
    case_stdout() { # <label> <expected file> <args...>
        local label="$1" file="$2"; shift 2
        run_digest "$@"
        [ "$CODE" = 0 ] && [ "$OUT" = "$(cat "$fixtures/$file")" ]; check "$label" $?
        if [ "$failed" = 1 ] && [ "$OUT" != "$(cat "$fixtures/$file")" ]; then
            printf '%s\n' "$OUT" | diff "$fixtures/$file" - | sed 's/^/     /'
        fi
    }
    case_usage() { # <label> <args...>
        local label="$1"; shift
        run_digest "$@"
        [ "$CODE" = 2 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -qF 'usage: scripts/skill-changes-digest.sh [--since YYYY-MM-DD]'
        check "$label: exit 2, usage on stderr, nothing on stdout" $?
    }

    case_stdout "since 2026-01-01: first parent, oldest first, watched paths, +/- lines" since-2026-01-01.stdout --since 2026-01-01
    case_stdout "since 2026-01-15: the date itself counts, earlier commits do not" since-2026-01-15.stdout --since 2026-01-15
    case_stdout "since 2026-01-21: no commits" no-changes.stdout --since 2026-01-21
    run_digest --since 2032-02-29
    [ "$CODE" = 0 ] && [ "$OUT" = "no changes to skills or CLAUDE.md since 2032-02-29" ]; check "leap day 2032-02-29 is a valid date" $? $?
    run_digest
    [ "$CODE" = 0 ] && printf '%s' "$OUT" | grep -qE '^no changes to skills or CLAUDE.md since [0-9]{4}-[0-9]{2}-[0-9]{2}$'; check "default window (last 7 days) runs" $? $?
    case_usage "bad date 2026-13-01" --since 2026-13-01
    case_usage "bad date 2026-02-30" --since 2026-02-30
    case_usage "bad date 2030-02-29 (not a leap year)" --since 2030-02-29
    case_usage "bad date 2100-02-29 (century year, not a leap year)" --since 2100-02-29
    case_usage "bad date format 2026-1-1" --since 2026-1-1
    case_usage "--since without a value" --since
    case_usage "unknown option" --bogus
    case_usage "positional argument" 2026-01-01

    git -C "$repo" update-ref -d refs/remotes/origin/main || return 2
    run_digest --since 2026-01-01
    [ "$CODE" = 2 ] && printf '%s' "$ERR" | grep -qF 'origin/main not found'; check "no origin/main: exit 2 and says so" $?

    if [ "$failed" = 0 ]; then echo "skill-changes-digest: self-test passed"; else echo "skill-changes-digest: self-test FAILED"; fi
    return "$failed"
}

SINCE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --self-test)
            [ $# -eq 1 ] || usage
            self_test
            exit $?
            ;;
        --since)
            [ $# -ge 2 ] || usage
            SINCE="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

if [ -z "$SINCE" ]; then
    SINCE="$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d 2>/dev/null)" || SINCE=""
fi
if ! valid_date "$SINCE"; then
    echo "skill-changes-digest: not a valid date: '$SINCE'" >&2
    usage
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
REF="origin/main"
PATHS=(".claude/skills/" ":(glob)**/CLAUDE.md")

if ! git rev-parse -q --verify "$REF^{commit}" >/dev/null; then
    echo "skill-changes-digest: $REF not found (git fetch origin)" >&2
    exit 2
fi
if ! COMMITS="$(git log --first-parent --reverse --format=%H --since="$SINCE 00:00:00" "$REF" -- "${PATHS[@]}")"; then
    echo "skill-changes-digest: git log failed" >&2
    exit 2
fi

if [ -z "$COMMITS" ]; then
    echo "no changes to skills or CLAUDE.md since $SINCE"
    exit 0
fi

COUNT=0
for C in $COMMITS; do
    COUNT=$((COUNT + 1))
    git log -1 --format='%h %cd %s' --date=short "$C" || exit 2
    if git rev-parse -q --verify "$C^1" >/dev/null; then
        DIFF="$(git diff --no-color --no-ext-diff --no-textconv --no-renames -U0 "$C^1" "$C" -- "${PATHS[@]}")" || exit 2
    else
        DIFF="$(git diff-tree -p --root --no-color --no-ext-diff --no-textconv --no-renames -U0 "$C" -- "${PATHS[@]}")" || exit 2
    fi
    # File headers become `    <path>`; inside hunks only `+` and `-` lines are kept.
    printf '%s\n' "$DIFF" | awk '
        /^diff --git / { inhunk = 0; next }
        /^\+\+\+ / && !inhunk { path = substr($0, 5); sub(/^b\//, "", path)
                               if (path == "/dev/null") path = old
                               print "    " path; next }
        /^--- / && !inhunk { old = substr($0, 5); sub(/^a\//, "", old); next }
        /^@@ / { inhunk = 1; next }
        inhunk && /^[-+]/ { print "      " $0 }
    '
done
if [ "$COUNT" -eq 1 ]; then
    echo "1 commit touched skills or CLAUDE.md since $SINCE"
else
    echo "$COUNT commits touched skills or CLAUDE.md since $SINCE"
fi
