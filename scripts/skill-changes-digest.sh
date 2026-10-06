#!/usr/bin/env bash
# Skill changes digest: what changed in the skills and CLAUDE.md files on main since a date, so the
# human can see after the fact what agents changed in the reference skills (which they may edit
# without his review) and revert anything (docs/epics/protected-paths-review.md, Decision 6).
#
#   scripts/skill-changes-digest.sh [--since YYYY-MM-DD]   default: the last 7 days
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

SINCE=""
while [ $# -gt 0 ]; do
    case "$1" in
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
