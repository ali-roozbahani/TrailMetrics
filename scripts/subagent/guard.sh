#!/usr/bin/env bash
# Claude Code PreToolUse hook of the `implementer` subagent (.claude/agents/implementer.md, `hooks:`
# in its front matter, so it runs only while that subagent runs). It keeps the implementer inside its
# own git worktree and its allowed paths, and away from everything that leaves the machine or belongs
# to the orchestrator. Wire format as the other hooks (scripts/claude-hooks/block-git-push.sh): stdin
# JSON with `.tool_name`, `.tool_input` and `.cwd`; exit 0 = no decision (the normal permission flow
# goes on), exit 2 = block, stderr is the reason fed back to the subagent.
#
# The worktree and its allowed paths come from `.cwd`: the git work tree it is in must be a linked
# worktree with the `tm-subagent` record that scripts/subagent/worktree.sh create writes (in the
# worktree's own git directory). From the main clone, another directory, or a worktree without the
# record, every call is blocked (fail closed). The record's `allowed` list is read through
# `worktree.sh check-path`, the same matcher `worktree.sh take` applies to the commits afterwards.
#
# Write, Edit, MultiEdit, NotebookEdit: the target must resolve (directories through `cd -P`, so a
#   link in the path is followed) to a file inside the worktree, not be a symbolic link itself, have no
#   `..` component and be an allowed path.
# Read, Grep, Glob: refused when they name, or resolve to, the git-ignored secrets files (the iOS
#   secrets config, `local.properties`, `.env*`). The worktree path of such a file is not covered by the
#   rooted deny rules of .claude/settings.json; that is why this exists.
# Bash: refused when the command has, as a word of a simple command: `git push`, `git remote`,
#   `git config`, `git credential`, `git update-ref`, `git worktree`, `git fetch`, `git pull`; `gh`
#   (pull requests, merges, the API); `claude`; `curl`, `wget`, `ssh`, `scp`, `rsync`; the orchestrator's
#   scripts (`scripts/subagent/worktree.sh`, `scripts/queue/`, `scripts/local-review`,
#   `scripts/set-pr-body.sh`, `scripts/pre-push-check.sh`, the gate); or a `cd`/`pushd` whose target
#   leaves the worktree or cannot be read (`..`, `~`, `-`, a variable, an absolute path elsewhere).
#   The word match is on the text, so a harmless command that spells one of these (`git log --grep
#   push`) is refused too; the reason says to rephrase.
#
# What it does not do: it reads command text. A write through a shell redirection, `sed -i`, `tee`, a
# script the implementer wrote and runs, or a path built from a variable is not seen, and a Bash call
# that leaves the worktree without `cd` text (`git -C /elsewhere`) is not caught except for the words
# above. `worktree.sh take` refuses afterwards any commit outside the allowed paths, and the
# orchestrator reviews the diff, which is the check that does not depend on this hook. Whether this
# hook fires for a subagent's tool calls, and what `.cwd` holds there, are in the report of the PR that
# added it as "not verified" until a real run shows them.
#
# Needs jq. BREAK-GLASS (human only): remove the `hooks:` block from .claude/agents/implementer.md.
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$SCRIPT_DIR/worktree.sh"
SECRETS_RE='(Secrets\.xcconfig|(^|/)local\.properties|(^|/)\.env([^/]*)?$)'

deny() { echo "implementer guard: $*" >&2; exit 2; }

guard() {
    local input tool cwd root gitdir common rec p abs real dir rest base rel cmd seg word
    input="$(cat)"
    command -v jq >/dev/null 2>&1 || deny "jq is missing, so this hook cannot read the call"
    tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || deny "unreadable hook input"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)" || deny "unreadable hook input"
    [ -n "$cwd" ] && [ -d "$cwd" ] || deny "the hook input has no readable working directory"
    root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || deny "$cwd is not inside a git work tree"
    root="$(cd "$root" && pwd -P)"
    gitdir="$(git -C "$root" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || deny "cannot read the git directory of $root"
    common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || deny "cannot read the git directory of $root"
    [ "$gitdir" != "$common" ] || deny "$root is the main clone: the implementer works only in its own worktree (scripts/subagent/worktree.sh create)"
    rec="$(git -C "$root" rev-parse --path-format=absolute --git-path tm-subagent 2>/dev/null)"
    [ -f "$rec/allowed" ] || deny "$root has no tm-subagent record: it was not created by scripts/subagent/worktree.sh"

    case "$tool" in
        Write | Edit | MultiEdit | NotebookEdit)
            p="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
            [ -n "$p" ] || deny "$tool without a file path"
            case "$p" in /*) abs="$p" ;; *) abs="$cwd/$p" ;; esac
            case "/$abs/" in */../*) deny "'$p' has a '..' component" ;; esac
            # Resolve the deepest existing directory with cd -P, then append the rest.
            dir="$(dirname "$abs")"; rest="$(basename "$abs")"
            while [ ! -d "$dir" ] && [ "$dir" != / ]; do rest="$(basename "$dir")/$rest"; dir="$(dirname "$dir")"; done
            real="$(cd "$dir" && pwd -P)/$rest"
            [ ! -L "$abs" ] || deny "'$p' is a symbolic link; the implementer does not write through links"
            case "$real" in "$root"/*) ;; *) deny "'$p' is outside the worktree $root" ;; esac
            rel="${real#"$root"/}"
            bash "$WORKTREE" check-path "$root" "$rel" || deny "'$rel' is not one of the allowed paths: $(tr '\n' ' ' < "$rec/allowed")"
            ;;
        Read | Grep | Glob)
            p="$(printf '%s' "$input" | jq -r '[.tool_input.file_path, .tool_input.path, .tool_input.pattern, .tool_input.glob] | map(select(. != null)) | join("\n")' 2>/dev/null)"
            while IFS= read -r word; do
                [ -n "$word" ] || continue
                printf '%s' "$word" | grep -Eq "$SECRETS_RE" && deny "'$word' names a git-ignored secrets file; it is not read"
                case "$word" in /*) abs="$word" ;; *) abs="$cwd/$word" ;; esac
                if [ -L "$abs" ]; then
                    real="$(cd "$(dirname "$abs")" 2>/dev/null && cd "$(dirname "$(readlink "$abs")")" 2>/dev/null && pwd -P)/$(basename "$(readlink "$abs")")"
                    printf '%s' "$real" | grep -Eq "$SECRETS_RE" && deny "'$word' is a link to a git-ignored secrets file; it is not read"
                fi
            done <<< "$p"
            ;;
        Bash)
            cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
            [ -n "$cmd" ] || exit 0
            if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_.-])git[^;&|]*[[:space:]](push|remote|config|credential|update-ref|worktree|fetch|pull)([[:space:]]|$)'; then
                deny "a git command that pushes, changes remotes, config, refs or worktrees, or fetches is not allowed here; commit in this worktree and stop (the orchestrator takes the commits). If this was a harmless command that only spells one of those words, rephrase it."
            fi
            if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_.-])([^[:space:];&|]*/)?(gh|claude|curl|wget|ssh|scp|rsync)([[:space:]]|$)'; then
                deny "gh, claude, curl, wget, ssh, scp and rsync are not allowed here: opening, reviewing or merging a PR and anything that leaves the machine is the orchestrator's"
            fi
            if printf '%s' "$cmd" | grep -Eq 'scripts/(subagent/worktree\.sh|queue/|local-review|set-pr-body\.sh|pre-push-check\.sh|main-ci-status\.sh|wait-for-checks\.sh)'; then
                deny "that script belongs to the orchestrator (worktrees, queue, review, gate, CI); run the module's tests with scripts/heavy-run.sh ./gradlew ... instead"
            fi
            # cd / pushd must stay inside the worktree.
            while IFS= read -r seg; do
                set -- $seg
                [ "${1:-}" = cd ] || [ "${1:-}" = pushd ] || continue
                p="${2:-}"
                case "$p" in
                    '' | - | '~'* | *'$'* | *'`'* | .. | ../* | */.. | */../*) deny "cd '$p' leaves the worktree or cannot be read" ;;
                    /*) real="$(cd "$p" 2>/dev/null && pwd -P)" || deny "cd '$p': no such directory"
                        case "$real/" in "$root"/*) ;; *) deny "cd '$p' leaves the worktree $root" ;; esac ;;
                esac
            done <<< "$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||;|\||&|\(|\)|`)/\n/g')"
            ;;
    esac
    exit 0
}

self_test() {
    local tmp fails=0 repo wt out rc other
    tmp="$(cd "$(mktemp -d)" && pwd -P)"
    TMP_ROOT="$tmp"
    trap 'rm -rf -- "$TMP_ROOT"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null TM_WORKTREE_DIR="$tmp/wts"
    command -v jq >/dev/null 2>&1 || { echo "guard self-test: jq is needed" >&2; return 1; }
    repo="$tmp/repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name t
    mkdir -p "$repo/src" "$repo/docs"
    echo one > "$repo/src/a.txt"; echo two > "$repo/docs/b.txt"
    printf 'iosApp/TrailMetrics/Secrets.xcconfig\nlocal.properties\n' > "$repo/.gitignore"
    git -C "$repo" add -A && git -C "$repo" commit -q -m base
    : > "$repo/local.properties"
    (cd "$repo" && bash "$WORKTREE" create impl --from main --allow src --allow docs/new.txt --android) >/dev/null
    wt="$tmp/wts/impl"
    ln -s "$tmp/outside.txt" "$wt/src/link.txt"
    git -C "$repo" worktree add -q -b plain "$tmp/plain" main
    other="$tmp/nongit"; mkdir -p "$other"
    run() { # run <cwd> <json tool input> <tool>: the guard's exit status
        jq -n --arg cwd "$1" --arg tool "$3" --argjson ti "$2" '{tool_name: $tool, tool_input: $ti, cwd: $cwd}' | bash "${BASH_SOURCE[0]}" 2>"$tmp/err"
    }
    expect() { # expect <description> <exit> <cwd> <tool> <json tool input> [<substring of the reason>]
        local d="$1" want="$2" cwd="$3" tool="$4" ti="$5" sub="${6:-}"
        run "$cwd" "$ti" "$tool"; rc=$?
        if [ "$rc" = "$want" ] && { [ -z "$sub" ] || grep -qF -- "$sub" "$tmp/err"; }; then echo "ok   $d"; else
            echo "FAIL $d: expected exit $want${sub:+ and '$sub'}, got exit $rc: $(cat "$tmp/err")" >&2; fails=$((fails + 1)); fi
    }
    bash_in() { jq -n --arg c "$1" '{command: $c}'; }
    file_in() { jq -n --arg p "$1" '{file_path: $p}'; }

    expect "write to an allowed directory" 0 "$wt" Write "$(file_in "$wt/src/deep/new.kt")"
    expect "write to the allowed file" 0 "$wt" Edit "$(file_in "$wt/docs/new.txt")"
    expect "a relative path resolves against the cwd" 0 "$wt/src" Write "$(file_in "x.kt")"
    expect "a path outside the allowed ones" 2 "$wt" Write "$(file_in "$wt/docs/b.txt")" "not one of the allowed paths"
    expect "a path outside the worktree" 2 "$wt" Write "$(file_in "$tmp/elsewhere.txt")" "outside the worktree"
    expect "the main clone's file" 2 "$wt" Edit "$(file_in "$repo/src/a.txt")" "outside the worktree"
    expect "a '..' component" 2 "$wt" Write "$(file_in "$wt/src/../docs/b.txt")" "'..' component"
    expect "the .git file" 2 "$wt" Write "$(file_in "$wt/.git")"
    expect "a symbolic link as the target" 2 "$wt" Write "$(file_in "$wt/src/link.txt")" "symbolic link"
    expect "a notebook path" 0 "$wt" NotebookEdit "$(jq -n --arg p "$wt/src/n.ipynb" '{notebook_path: $p}')"
    expect "a write without a path" 2 "$wt" Write '{}' "without a file path"

    expect "a normal read" 0 "$wt" Read "$(file_in "$wt/src/a.txt")"
    expect "a read of local.properties" 2 "$wt" Read "$(file_in "$wt/local.properties")" "secrets file"
    expect "a read of the iOS secrets config" 2 "$wt" Read "$(file_in "$wt/iosApp/TrailMetrics/Secrets.xcconfig")" "secrets file"
    expect "a grep that names a secrets file" 2 "$wt" Grep "$(jq -n '{pattern: "KEY", glob: "**/local.properties"}')" "secrets file"
    expect "a glob of src" 0 "$wt" Glob "$(jq -n '{pattern: "src/**/*.kt"}')"

    expect "gradle through the lock" 0 "$wt" Bash "$(bash_in 'scripts/heavy-run.sh ./gradlew :domain:allTests')"
    expect "git status and commit" 0 "$wt" Bash "$(bash_in 'git status && git add -A && git commit -q -m x')"
    expect "git push" 2 "$wt" Bash "$(bash_in 'git push origin HEAD')" "pushes"
    expect "git -C . push" 2 "$wt" Bash "$(bash_in 'git -C . push -u origin chore/x')"
    expect "a push after other commands" 2 "$wt" Bash "$(bash_in 'echo hi && git push')"
    expect "git remote" 2 "$wt" Bash "$(bash_in 'git remote add x y')"
    expect "git fetch" 2 "$wt" Bash "$(bash_in 'git fetch origin')"
    expect "gh pr create" 2 "$wt" Bash "$(bash_in 'gh pr create --fill')" "orchestrator's"
    expect "gh by its path" 2 "$wt" Bash "$(bash_in '/opt/homebrew/bin/gh pr merge 5')"
    expect "curl" 2 "$wt" Bash "$(bash_in 'curl https://example.com')"
    expect "the worktree script" 2 "$wt" Bash "$(bash_in 'scripts/subagent/worktree.sh take impl')" "orchestrator"
    expect "the gate" 2 "$wt" Bash "$(bash_in 'scripts/pre-push-check.sh')"
    expect "the queue" 2 "$wt" Bash "$(bash_in 'scripts/queue/queue.sh show')"
    expect "cd into a subdirectory" 0 "$wt" Bash "$(bash_in 'cd src && ls')"
    expect "cd to an absolute path inside" 0 "$wt" Bash "$(bash_in "cd $wt/src && ls")"
    expect "cd to /tmp" 2 "$wt" Bash "$(bash_in 'cd /tmp && ls')" "leaves the worktree"
    expect "cd .." 2 "$wt" Bash "$(bash_in 'cd .. && ls')"
    expect "cd to a variable" 2 "$wt" Bash "$(bash_in 'cd $HOME && ls')"
    expect "cd ~" 2 "$wt" Bash "$(bash_in 'cd ~ && ls')"
    expect "a command in a subdirectory of the worktree" 0 "$wt/src" Bash "$(bash_in 'ls')"
    expect "an empty Bash command" 0 "$wt" Bash '{}'
    expect "a tool the guard does not judge" 0 "$wt" WebSearch '{}'

    expect "the main clone is refused" 2 "$repo" Write "$(file_in "$repo/src/x")" "main clone"
    expect "a worktree without a record is refused" 2 "$tmp/plain" Write "$(file_in "$tmp/plain/src/x")" "tm-subagent record"
    expect "a directory outside git is refused" 2 "$other" Bash "$(bash_in 'ls')" "not inside a git work tree"

    if [ "$fails" -eq 0 ]; then echo "guard.sh self-test: all passed"; else echo "guard.sh self-test: $fails failed" >&2; fi
    [ "$fails" -eq 0 ]
}

case "${1:-}" in
    --self-test) [ $# -eq 1 ] || { echo "usage: scripts/subagent/guard.sh --self-test (a hook otherwise: JSON on stdin)" >&2; exit 2; }; self_test; exit $? ;;
    "") guard ;;
    *) echo "usage: scripts/subagent/guard.sh --self-test (a hook otherwise: JSON on stdin)" >&2; exit 2 ;;
esac
