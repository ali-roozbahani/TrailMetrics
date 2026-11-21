#!/usr/bin/env bash
# The report of an epic run must name every protected-path file the run changed (running-an-epic.md, step 5). In the
# first run the last fix changed one skill file that no earlier commit had touched, and the report did not say so.
#
#   scripts/epic/check-report.sh <report file> [--base <ref>]     (default base: origin/main; run on the integration branch)
#   scripts/epic/check-report.sh --self-test
#
# Lists the protected files of `git diff <base>...HEAD` (scripts/check-protected-paths.sh, which reads CODEOWNERS) and
# checks that each path appears in <report file>: the epic PR's description, and the text of the final report (write
# the report to a file first). Prints `PROTECTED_CHANGED <n>` and one line per file, `listed` or `MISSING`. Exit 0 when
# every file is listed (or there are none), 1 when one is missing, 2 usage error or an unreadable file. Run it again
# after every commit that follows the report: the check reads the branch as it is now.
# Bash 3.2 compatible.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
CLASSIFIER="${TM_PROTECTED_CLASSIFIER:-$SCRIPT_DIR/../check-protected-paths.sh}"
USAGE="usage: scripts/epic/check-report.sh <report file> [--base <ref>] | --self-test"

# names_path <path> <report file>: the path appears in the report as a whole path, not as a part of a longer one: not
# after a path character (`docs/BOARD.md` does not name `BOARD.md`), and not before one that continues it
# (`SKILL.md.bak`, `SKILL.md/x`, `SKILL.mdx`); a sentence's period or comma after the path is not a continuation.
names_path() {
    python3 -I - "$1" "$2" <<'PY'
import re, sys
path, report = sys.argv[1], sys.argv[2]
text = open(report, encoding="utf-8", errors="replace").read()
pattern = r"(?<![A-Za-z0-9_./-])" + re.escape(path) + r"(?![A-Za-z0-9_/-])(?!\.[A-Za-z0-9_])"
sys.exit(0 if re.search(pattern, text) else 1)
PY
}

check() {
    local report="$1" base="$2" out files f missing=0 n
    [ -r "$report" ] || { echo "check-report: cannot read $report" >&2; return 2; }
    out="$("$CLASSIFIER" --base "$base" 2>&1)" || { echo "check-report: the classifier failed: $out" >&2; return 2; }
    files="$(printf '%s\n' "$out" | sed '1d' | sed 's/  (.*$//' | sed '/^$/d')"
    n="$(printf '%s' "$files" | grep -c . || true)"
    echo "PROTECTED_CHANGED $n"
    [ -n "$files" ] || return 0
    while IFS= read -r f; do
        if names_path "$f" "$report"; then echo "  listed   $f"; else echo "  MISSING  $f"; missing=$((missing + 1)); fi
    done <<EOF2
$files
EOF2
    if [ "$missing" -gt 0 ]; then echo "check-report: $missing protected file(s) changed by the run are not named in $report" >&2; return 1; fi
    return 0
}

self_test() {
    local tmp fails=0 out rc
    tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
    printf '#!/bin/sh\nprintf "protected\\n.claude/skills/x/SKILL.md  (.claude/)\\nBOARD.md  (/BOARD.md)\\n"\n' > "$tmp/classify"
    printf '#!/bin/sh\nprintf "unprotected\\n"\n' > "$tmp/none"
    chmod +x "$tmp/classify" "$tmp/none"
    t() { # t <description> <expected substring> <expected exit> <classifier> <report text>
        printf '%s\n' "$5" > "$tmp/report"
        out="$(TM_PROTECTED_CLASSIFIER="$4" bash "$SELF" "$tmp/report" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$3" ] && printf '%s' "$out" | grep -qF -- "$2"; then echo "ok   $1"
        else echo "FAIL $1: expected exit $3 and '$2', got exit $rc: $out" >&2; fails=$((fails + 1)); fi
    }
    t "every protected file named passes" "PROTECTED_CHANGED 2" 0 "$tmp/classify" "changed .claude/skills/x/SKILL.md and BOARD.md"
    t "a file left out fails" "MISSING  BOARD.md" 1 "$tmp/classify" "changed .claude/skills/x/SKILL.md only"
    t "the failure says how many" "1 protected file(s) changed by the run are not named" 1 "$tmp/classify" ".claude/skills/x/SKILL.md"
    t "a path inside a longer one does not name it" "MISSING  BOARD.md" 1 "$tmp/classify" ".claude/skills/x/SKILL.md and docs/BOARD.md"
    t "a longer path that continues it does not name it" "MISSING  .claude/skills/x/SKILL.md" 1 "$tmp/classify" ".claude/skills/x/SKILL.md.bak and BOARD.md"
    t "a path before a sentence's period or in backticks is named" "PROTECTED_CHANGED 2" 0 "$tmp/classify" "changed \`.claude/skills/x/SKILL.md\`, and BOARD.md."
    t "no protected file passes" "PROTECTED_CHANGED 0" 0 "$tmp/none" "nothing"
    t "a classifier that fails is an error" "the classifier failed" 2 "$tmp/missing-classifier" "x"
    out="$(bash "$SELF" 2>&1)"; rc=$?
    if [ "$rc" = 2 ]; then echo "ok   usage error exits 2"; else echo "FAIL usage error: exit $rc" >&2; fails=$((fails + 1)); fi
    if [ "$fails" = 0 ]; then echo "check-report.sh self-test: all passed"; else echo "check-report.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]; exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    "" | -*) echo "$USAGE" >&2; exit 2 ;;
    *)
        if [ "$#" = 1 ]; then check "$1" origin/main; exit $?
        elif [ "$#" = 3 ] && [ "$2" = --base ]; then check "$1" "$3"; exit $?
        else echo "$USAGE" >&2; exit 2; fi ;;
esac
