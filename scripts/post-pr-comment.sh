#!/usr/bin/env bash
# Posts a PR comment (the "Merge check" comment, tm-agent-loop, "Auto-merge") and makes sure it exists.
#
#   scripts/post-pr-comment.sh <PR number> <body file>
#   scripts/post-pr-comment.sh --self-test
#
# In one run `gh pr comment` printed nothing and posted nothing, and the agent noticed only by looking. This script
# never trusts a post: after each try it reads the PR's comments through the REST API and looks for one whose body
# is exactly the file's text (trailing newlines ignored). The order: `gh pr comment <N> --body-file <file>`; if no such
# comment exists afterwards, `POST repos/{owner}/{repo}/issues/<N>/comments` through `gh api`; if still none, it fails.
# A comment already there with that exact body (an earlier try that did land) is not posted a second time.
#
# Output: `POSTED gh <url>` or `POSTED rest <url>` (the url of the comment), `EXISTS <url>` when the comment was there
# before the first try. Exit 0 posted or exists, 1 neither route produced a comment (the last error of each is printed
# on stderr; the PR has no such comment: do not go on as if it had), 2 usage error or an unreadable file.
# Environment: GH (the gh command, for the self-test). Bash 3.2 compatible; needs jq.
set -u
GH="${GH:-gh}"
USAGE="usage: scripts/post-pr-comment.sh <PR number> <body file> | --self-test"

# find_comment <PR> <body file> -> prints the html_url of a comment with exactly that body, else nothing
find_comment() {
    local pr="$1" file="$2" want
    want="$(jq -Rs 'sub("\n+$"; "")' "$file")" || return 1
    "$GH" api --paginate "repos/{owner}/{repo}/issues/$pr/comments?per_page=100" 2>/dev/null \
        | jq -r --argjson want "$want" '[.[] | select((.body | gsub("\r"; "") | sub("\n+$"; "")) == $want)] | last | .html_url // empty' 2>/dev/null
}

post() {
    local pr="$1" file="$2" url err
    [[ "$pr" =~ ^[0-9]+$ ]] || { echo "$USAGE" >&2; return 2; }
    [ -r "$file" ] && [ -s "$file" ] || { echo "post-pr-comment: cannot read a non-empty $file" >&2; return 2; }
    url="$(find_comment "$pr" "$file")"
    if [ -n "$url" ]; then echo "EXISTS $url"; return 0; fi
    err="$("$GH" pr comment "$pr" --body-file "$file" 2>&1 >/dev/null)"
    url="$(find_comment "$pr" "$file")"
    if [ -n "$url" ]; then echo "POSTED gh $url"; return 0; fi
    echo "post-pr-comment: gh pr comment did not leave a comment${err:+ (it said: ${err%%$'\n'*})}; trying the REST API" >&2
    err="$(jq -Rs '{body: .}' "$file" | "$GH" api -X POST "repos/{owner}/{repo}/issues/$pr/comments" --input - 2>&1 >/dev/null)"
    url="$(find_comment "$pr" "$file")"
    if [ -n "$url" ]; then echo "POSTED rest $url"; return 0; fi
    echo "post-pr-comment: FAILED: neither gh pr comment nor the REST API left the comment on PR $pr${err:+ (REST said: ${err%%$'\n'*})}" >&2
    return 1
}

self_test() {
    local tmp fails=0 out rc
    tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
    # A fake gh over a directory: `api .../comments` lists $FAKE/comments.json; `pr comment` appends one unless
    # $FAKE/gh-silent exists (it prints nothing and posts nothing); `api -X POST` appends one unless $FAKE/rest-fails.
    cat > "$tmp/gh" <<'FAKE'
#!/bin/bash
F="$FAKE_DIR"
add() { jq --arg b "$1" '. + [{body:$b, html_url:("https://x/comment/"+(length|tostring))}]' "$F/comments.json" > "$F/c.tmp" && mv "$F/c.tmp" "$F/comments.json"; }
if [ "$1" = api ] && [ "$2" = -X ]; then [ -e "$F/rest-fails" ] && { echo "HTTP 403" >&2; exit 1; }; add "$(cat | jq -r .body)"; exit 0; fi
if [ "$1" = api ]; then cat "$F/comments.json"; exit 0; fi
if [ "$1" = pr ] && [ "$2" = comment ]; then [ -e "$F/gh-silent" ] && exit 0; add "$(cat "$5")"; exit 0; fi
exit 1
FAKE
    chmod +x "$tmp/gh"
    printf 'Merge check\n\n1. yes\n' > "$tmp/body"
    t() { # t <description> <expected substring> <expected exit>
        out="$(GH="$tmp/gh" FAKE_DIR="$tmp" bash "$0" 7 "$tmp/body" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$3" ] && printf '%s' "$out" | grep -qF -- "$2"; then echo "ok   $1"
        else echo "FAIL $1: expected exit $3 and '$2', got exit $rc: $out" >&2; fails=$((fails + 1)); fi
    }
    echo '[]' > "$tmp/comments.json"; rm -f "$tmp/gh-silent" "$tmp/rest-fails"
    t "gh posts it and the script verifies it" "POSTED gh https://x/comment/0" 0
    t "a comment already there is not posted again" "EXISTS https://x/comment/0" 0
    echo '[]' > "$tmp/comments.json"; touch "$tmp/gh-silent"
    t "a gh that prints nothing and posts nothing falls back to REST" "POSTED rest https://x/comment/0" 0
    echo '[]' > "$tmp/comments.json"; touch "$tmp/rest-fails"
    t "neither route fails loudly" "FAILED: neither gh pr comment nor the REST API left the comment on PR 7" 1
    echo '[{"body":"Merge check\n\n1. no","html_url":"u"}]' > "$tmp/comments.json"; rm -f "$tmp/rest-fails" "$tmp/gh-silent"
    t "a different comment does not count as the posted one" "POSTED gh" 0
    out="$(bash "$0" 2>&1)"; rc=$?
    if [ "$rc" = 2 ]; then echo "ok   usage error exits 2"; else echo "FAIL usage error: exit $rc" >&2; fails=$((fails + 1)); fi
    out="$(GH="$tmp/gh" FAKE_DIR="$tmp" bash "$0" 7 "$tmp/none" 2>&1)"; rc=$?
    if [ "$rc" = 2 ]; then echo "ok   an unreadable body is a usage error"; else echo "FAIL unreadable body: exit $rc" >&2; fails=$((fails + 1)); fi
    if [ "$fails" = 0 ]; then echo "post-pr-comment.sh self-test: all passed"; else echo "post-pr-comment.sh self-test: $fails failed" >&2; fi
    [ "$fails" = 0 ]; exit $?
}

case "${1:-}" in
    --self-test) [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }; self_test ;;
    "" | -*) echo "$USAGE" >&2; exit 2 ;;
    *) [ "$#" = 2 ] || { echo "$USAGE" >&2; exit 2; }; post "$1" "$2"; exit $? ;;
esac
