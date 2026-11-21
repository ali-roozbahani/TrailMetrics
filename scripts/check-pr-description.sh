#!/usr/bin/env bash
# Checks a PR description draft against the rules the CI reviewer reads it by, before the first push.
#
#   scripts/check-pr-description.sh <draft>            the structure (the same rules `tm-pr-review`, item 8 and `tm-pr-workflow`, "PR description" give)
#   scripts/check-pr-description.sh --final <draft>    the structure and "ready to be the description of the pushed PR"
#   scripts/check-pr-description.sh --self-test
#
# CI's reviewer reads the description when its run starts, so the description is final before the first push; in #364 the
# first push went out with a description the reviewer found wanting (bullets of "Follow-ups" with no `(queue: ...)` ending)
# and a later edit was read late. Problems, one per line on stdout, exit 1; none: `OK`, exit 0; usage error: exit 2.
# Structure: the four headings (What changed, Skills/docs followed, Tier 1, Tier 2); a `Board:` line; each bullet under a
# "Follow-ups" or "Drift found" heading ends with `(#<n>)`, `(queue: <slug>)` or `(board: <slug>)` (a bullet "None" is
# exempt); the draft is not the CI reviewer's `Reviewer findings`-less first form only: nothing else is checked.
# --final adds: no `Pending` placeholder (the gate's result is written in Tier 1), and the attribution line the session specifies
# (`Generated with [Claude Code]`) ends the description.
# Bash 3.2 compatible; python3 (standard library) does the reading.
set -u
USAGE="usage: scripts/check-pr-description.sh [--final] <draft> | --self-test"

check() {
    python3 -I - "$1" "$2" <<'PY'
import re, sys
final = sys.argv[1] == "final"
text = open(sys.argv[2], encoding="utf-8").read().replace("\r", "")
lines = text.split("\n")
if lines and lines[0].startswith("Title:"):
    lines = lines[1:]
problems = []
heads = [re.sub(r"[*_`#]", "", l).strip().lower() for l in lines if re.match(r"^\s*#{1,6}\s", l)]
for want in ("what changed", "skills/docs followed", "tier 1", "tier 2"):
    if not any(h.startswith(want) for h in heads):
        problems.append("missing heading: %s" % want)
if not any(re.match(r"^\s*Board:", re.sub(r"[*_`]", "", l)) for l in lines):
    problems.append("missing the `Board:` line (`Board: +slug, -slug` or `Board: no changes`)")
section = None
bullets = []
cur = None
for l in lines + ["## end"]:
    m = re.match(r"^\s*#{1,6}\s+(.*)$", l)
    if m:
        if cur is not None: bullets.append(cur); cur = None
        h = re.sub(r"[*_`]", "", m.group(1)).strip().lower()
        section = "follow" if (h.startswith("follow-ups") or h.startswith("drift found")) else None
        continue
    if section != "follow": continue
    if re.match(r"^\s*[-*]\s+", l):
        if cur is not None: bullets.append(cur)
        cur = l.strip()
    elif l.strip() == "":
        if cur is not None: bullets.append(cur); cur = None
    elif cur is not None:
        cur += " " + l.strip()
for b in bullets:
    body = re.sub(r"^[-*]\s+", "", b).strip()
    if re.fullmatch(r"none\.?", body, re.I): continue
    if not re.search(r"\((#\d+|queue: [a-z0-9-]+|board: [a-z0-9-]+)\)\.?\s*$", body):
        problems.append("a Follow-ups or Drift bullet has no (#n), (queue: slug) or (board: slug) ending: %s" % body[:80])
if final:
    for i, l in enumerate(lines):
        if re.search(r"\bPending\b.*\bgate\b", l) or re.search(r"\bTODO\b", l):
            problems.append("a placeholder is left (Tier 1 holds the gate's result before the push): %s" % l.strip()[:80])
    nonblank = [l for l in lines if l.strip()]
    if not nonblank or "Generated with [Claude Code]" not in nonblank[-1]:
        problems.append("the description does not end with the attribution line (Generated with [Claude Code])")
print("\n".join(problems) if problems else "OK")
sys.exit(1 if problems else 0)
PY
}

self_test() {
    local tmp fails=0 out rc
    tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
    good='## What changed\nx\n\n## Skills/docs followed\ny\n\n## Tier 1\nGate: exit 0.\n\n## Tier 2\nn\n\n## Follow-ups (out of scope, not changed)\n\n- a thing (queue: some-slug)\n- another (#12).\n\nBoard: no changes\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n'
    t() { # t <description> <expected substring> <expected exit> <text> [--final]
        printf "$4" > "$tmp/d.md"
        out="$(bash "$0" ${5:+"$5"} "$tmp/d.md" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$3" ] && printf '%s' "$out" | grep -qF -- "$2"; then echo "ok   $1"
        else echo "FAIL $1: expected exit $3 and '$2', got exit $rc: $out" >&2; fails=$((fails + 1)); fi
    }
    t "a complete description passes" "OK" 0 "$good" --final
    t "a follow-up bullet without an ending fails" "has no (#n), (queue: slug) or (board: slug) ending: a bare bullet" 1 "${good/- a thing (queue: some-slug)/- a bare bullet}"
    t "a continued bullet counts as one" "OK" 0 "${good/- a thing (queue: some-slug)/- a thing that goes on\n  over two lines (board: x)}"
    t "None is exempt" "OK" 0 "${good/- a thing (queue: some-slug)\n- another (#12)./None.}"
    t "a missing heading fails" "missing heading: tier 2" 1 "$(printf '%s' "$good" | sed 's/## Tier 2/## Something/')"
    t "a missing Board line fails" "missing the \`Board:\` line" 1 "${good/Board: no changes/}"
    t "a Title line is ignored" "OK" 0 "Title: fix(x): y\n\n$good"
    t "a placeholder fails with --final" "a placeholder is left" 1 "${good/Gate: exit 0./Pending the gate on the pushed HEAD.}" --final
    t "a placeholder passes without --final" "OK" 0 "${good/Gate: exit 0./Pending the gate on the pushed HEAD.}"
    t "no attribution fails with --final" "does not end with the attribution line" 1 "$(printf '%s' "$good" | sed 's/Generated with.*$//')" --final
    out="$(bash "$0" 2>&1)"; rc=$?
    if [ "$rc" = 2 ]; then echo "ok   usage error exits 2"; else echo "FAIL usage error: exit $rc" >&2; fails=$((fails + 1)); fi
    if [ "$fails" = 0 ]; then echo "check-pr-description.sh self-test: all passed"; else echo "check-pr-description.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]; exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    --final) [ "$#" = 2 ] && [ -r "$2" ] || { echo "$USAGE" >&2; exit 2; }; check final "$2" ;;
    "" | -*) echo "$USAGE" >&2; exit 2 ;;
    *) [ "$#" = 1 ] && [ -r "$1" ] || { echo "$USAGE" >&2; exit 2; }; check structure "$1" ;;
esac
