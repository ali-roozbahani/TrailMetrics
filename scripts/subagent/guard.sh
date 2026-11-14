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
# worktree's own git directory). Another directory, or a worktree without the record, blocks every call
# (fail closed). But a subagent's hook always gets the main clone as `cwd`: the shell is reset to
# it before every call and a `cd` does not last (two real runs showed it). So from the main clone the
# guard judges by what the call names: Read, Grep and Glob by the secrets names and by staying inside the
# main clone (an absolute path elsewhere is refused); Write, Edit and
# the like by their absolute target path, which must lie in a worktree under the worktree folder
# (then that worktree's allowed paths apply); Bash only when the command begins with
# `cd <the root of a worktree under the worktree folder>`, and the rest of it is judged as if the shell
# were there. The implementer therefore starts every Bash command with `cd <worktree> &&`. What the
# guard cannot tell is which worktree is the caller's own: an implementer could write into another
# implementer's worktree, within that worktree's allowed paths; the uncommitted change would show in the
# other worktree, whose `take` refuses it. The record's `allowed` list is read through
# `worktree.sh check-path`, the same matcher `worktree.sh take` applies to the commits afterwards.
#
# Write, Edit, MultiEdit, NotebookEdit: the target must resolve (directories through `cd -P`, so a
#   link in the path is followed) to a file inside the worktree, not be a symbolic link itself, have no
#   `..` component and be an allowed path.
# Read, Grep, Glob: refused when they name, or resolve to, the git-ignored secrets files (the iOS
#   secrets config, `local.properties`, `.env*`). The worktree path of such a file is not covered by the
#   rooted deny rules of .claude/settings.json; that is why this exists.
# Bash: refused when the command names a secrets file (the same names; the rooted deny rules of
#   .claude/settings.json also refuse a command that spells them, for any path). A command that reads
#   the linked file without spelling its name (`grep -R KEY .`, `cat *`, a glob) is not seen: the
#   orchestrator links the files (`--ios`, `--android`) only for an implementer that needs the build, and
#   the settings deny rules for the worktree's paths (given to the owner as text) are the second lock.
#   Also refused, as a word of a simple command: `git push`, `git remote`,
#   `git config`, `git credential`, `git update-ref`, `git worktree`, `git fetch`, `git pull`, and
#   `git -c`, `--config-env`, `--exec-path` or an `alias.` (an alias can be a push); `gh`
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
# orchestrator reviews the diff, which is the check that does not depend on this hook. Three real
# implementer runs showed that this hook fires for a subagent's tool calls, that its message reaches the
# subagent, and that `.cwd` is the main clone on every call (see the paragraph above). Whether `agent_id`
# (it would tell two implementers apart) is in the hook input is what the log below records.
#
# What it records. Every call, allowed or blocked, appends one tab-separated line to the guard log,
# ${TM_GUARD_LOG:-$HOME/agent-workspace/queue/subagent/guard.log} (outside the repository, in the
# queue folder that scripts/dev/clean-agent-workspace.sh keeps), and `scripts/subagent/guard.sh --log
# [<n>]` prints its last n lines (default 40). Columns: time, ALLOW or BLOCK, tool, agent_id,
# agent_type, the key names of the hook input, the call's cwd, and for a BLOCK the reason and the
# command or path that was blocked (at most 200 characters; none when the block is the secrets rule, as
# the text may hold a secret value). So a run answers, from the file:
#   - whether the hook input carries the subagent's id: the `agent_id` column is `-` when it does not,
#     and the key names show every field the input had;
#   - what a block inside a subagent was (the BLOCK lines, which the subagent only sees as a message);
# A call that gets no line never reached the hook. Nothing else is recorded (no file content, no
# command output). Writing the log can never change a decision: a log that cannot be written is ignored.
#
# Needs jq. BREAK-GLASS (human only): remove the `hooks:` block from .claude/agents/implementer.md.
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$SCRIPT_DIR/worktree.sh"
SECRETS_RE='(Secrets\.xcconfig|(^|/)local\.properties|(^|/)\.env([^/]*)?$)'
# The same names found anywhere in a command line (a word, not only a path component).
BASH_SECRETS_RE='(Secrets\.xcconfig|(^|[^[:alnum:]_.-])local\.properties|(^|[^[:alnum:]_])\.env([^[:alnum:]]|$))'

GUARD_LOG="${TM_GUARD_LOG:-$HOME/agent-workspace/queue/subagent/guard.log}"
LOG_PREFIX=""   # tool, agent_id, agent_type, input keys, cwd: set once the input is read
LOG_BLOCKED=""  # the command or path of the call, for a BLOCK line

# One line per call (see "What it records"). It runs as the EXIT trap, so every path out of guard() is
# logged, and it can never change the decision: its own failures are ignored and its status is dropped.
log_call() { # log_call <exit status of the guard> [<reason>]
    local verdict=ALLOW reason="${2:-}" blocked="$LOG_BLOCKED"
    [ "$1" = 0 ] || verdict=BLOCK
    # A command or path that names a secrets file may hold a secret value: its text is not logged.
    case "$reason" in *"secrets file"*) blocked="(not logged: it names a secrets file)" ;; esac
    [ -n "$LOG_PREFIX" ] || LOG_PREFIX="-	-	-	-	-"
    reason="$(printf '%s' "$reason" | tr '\t\r\n' '   ' | cut -c1-300)"
    blocked="$(printf '%s' "$blocked" | tr '\t\r\n' '   ' | cut -c1-200)"
    mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null || return 0
    if [ "$verdict" = BLOCK ]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$verdict" "$LOG_PREFIX" "$reason" "$blocked" >> "$GUARD_LOG" 2>/dev/null
    else
        printf '%s\t%s\t%s\t-\t-\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$verdict" "$LOG_PREFIX" >> "$GUARD_LOG" 2>/dev/null
    fi
    return 0
}

DENY_REASON=""
deny() { DENY_REASON="$*"; echo "implementer guard: $*" >&2; exit 2; }

guard() {
    local input tool cwd root gitdir common rec p abs real dir rest base rel cmd seg word
    local -a words
    local wts mainmsg first target check_record
    input="$(cat)"
    trap 'log_call $? "$DENY_REASON"' EXIT
    command -v jq >/dev/null 2>&1 || deny "jq is missing, so this hook cannot read the call"
    LOG_PREFIX="$(printf '%s' "$input" | jq -r '[.tool_name // "-", .agent_id // "-", .agent_type // "-", (keys | join(",")), .cwd // "-"] | @tsv' 2>/dev/null)" || LOG_PREFIX=""
    LOG_BLOCKED="$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.notebook_path // .tool_input.path // .tool_input.pattern // empty' 2>/dev/null)" || LOG_BLOCKED=""
    tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || deny "unreadable hook input"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)" || deny "unreadable hook input"
    [ -n "$cwd" ] && [ -d "$cwd" ] || deny "the hook input has no readable working directory"
    root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || deny "$cwd is not inside a git work tree"
    root="$(cd "$root" && pwd -P)"
    gitdir="$(git -C "$root" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || deny "cannot read the git directory of $root"
    common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || deny "cannot read the git directory of $root"
    check_record=1
    if [ "$gitdir" = "$common" ]; then
        # A subagent's hook always sees the main session's directory, the main clone, as `cwd`: a `cd`
        # does not last from one Bash call to the next (two real runs showed it), so nothing here can
        # rely on cwd. From the main clone: Read, Grep and Glob are judged by the secrets names and by staying
        # inside the main clone and the worktree folder (no `..`, no absolute path elsewhere); a
        # Write-family call by its absolute target path, which must lie in a worktree under the worktree
        # folder; a Bash command must begin with `cd <that worktree>` (every call, so the implementer
        # writes `cd <worktree> && ...`), and the rest of it is judged as if the shell were there.
        wts="${TM_WORKTREE_DIR:-$root/.claude/worktrees}"
        wts="$(cd "$wts" 2>/dev/null && pwd -P)" || deny "$root is the main clone and has no worktree folder: the implementer works only in its own worktree (scripts/subagent/worktree.sh create)"
        mainmsg="the shell of a subagent starts in the main clone $root every call: begin every Bash command with cd <your worktree> && and give Write and Edit the absolute path inside your worktree"
        case "$tool" in
            Read | Grep | Glob)
                check_record=0
                # Reads stay inside the main clone and the worktree folder (normally inside it): an absolute path elsewhere,
                # or one with a `..` component, is refused. A Grep pattern is a regular expression, not a path.
                p="$(printf '%s' "$input" | jq -r '[.tool_input.file_path, .tool_input.path, (if "'"$tool"'" == "Glob" then .tool_input.pattern else null end)] | map(select(. != null)) | join("\n")' 2>/dev/null)"
                while IFS= read -r word; do
                    # A `..` component in any word, relative ones included, could leave the clone.
                    case "/$word/" in */../*) deny "'$word' has a '..' component" ;; esac
                    case "$word" in
                        /*)
                            case "$word" in "$root" | "$root"/* | "$wts" | "$wts"/*) ;; *) deny "'$word' is outside the main clone $root and its worktree folder: Read, Grep and Glob stay inside them" ;; esac
                            ;;
                    esac
                done <<< "$p"
                ;;
            Write | Edit | MultiEdit | NotebookEdit)
                p="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
                case "$p" in /*) ;; *) deny "'$p' is not an absolute path. $mainmsg" ;; esac
                case "/$p/" in */../*) deny "'$p' has a '..' component" ;; esac
                dir="$(dirname "$p")"; rest="$(basename "$p")"
                while [ ! -d "$dir" ] && [ "$dir" != / ]; do rest="$(basename "$dir")/$rest"; dir="$(dirname "$dir")"; done
                real="$(cd "$dir" && pwd -P)/$rest"
                case "$real" in "$wts"/*) ;; *) deny "'$p' is not inside a worktree under $wts" ;; esac
                target="${real#"$wts"/}"
                target="${target%%/*}"
                case "$target" in '' | *.task.md) deny "'$p' is not inside a worktree under $wts" ;; esac
                root="$wts/$target"
                ;;
            Bash)
                cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
                first="$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||;|\||&).*//' | head -n 1)"
                read -r -a words <<< "$first"
                { [ "${words[0]:-}" = cd ] && [ -n "${words[1]:-}" ]; } || deny "$mainmsg"
                case "${words[1]}" in *'$'* | *'`'* | *'*'* | *'?'* | *'['* | '~'*) deny "$mainmsg" ;; esac
                case "${words[1]}" in /*) ;; *) deny "cd '${words[1]}' is not an absolute path. $mainmsg" ;; esac
                target="$(cd "${words[1]}" 2>/dev/null && pwd -P)" || deny "cd '${words[1]}': no such directory. $mainmsg"
                case "$target" in "$wts"/*) case "${target#"$wts"/}" in */*) deny "cd '${words[1]}' is not the root of a worktree. $mainmsg" ;; esac ;; *) deny "cd '${words[1]}' is not one of the worktrees under $wts. $mainmsg" ;; esac
                root="$target"
                cwd="$target"
                ;;
            *) deny "$mainmsg" ;;
        esac
    fi
    if [ "$check_record" = 1 ]; then
        rec="$(git -C "$root" rev-parse --path-format=absolute --git-path tm-subagent 2>/dev/null)"
        [ -f "$rec/allowed" ] || deny "$root has no tm-subagent record: it was not created by scripts/subagent/worktree.sh"
    fi

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
            if printf '%s' "$cmd" | grep -Eq "$BASH_SECRETS_RE"; then
                deny "the command names a git-ignored secrets file (the iOS secrets config, local.properties, .env*): it is not read, printed or copied"
            fi
            if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_.-])git[^;&|]*[[:space:]](-c|--config-env|--exec-path)([[:space:]=]|$)|alias\.'; then
                deny "git -c, --config-env, --exec-path and aliases can run another command under git's name: not allowed here"
            fi
            if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_.-])([^[:space:];&|]*/)?(gh|claude|curl|wget|ssh|scp|rsync)([[:space:]]|$)'; then
                deny "gh, claude, curl, wget, ssh, scp and rsync are not allowed here: opening, reviewing or merging a PR and anything that leaves the machine is the orchestrator's"
            fi
            if printf '%s' "$cmd" | grep -Eq 'scripts/(subagent/worktree\.sh|queue/|local-review|set-pr-body\.sh|pre-push-check\.sh|main-ci-status\.sh|wait-for-checks\.sh)'; then
                deny "that script belongs to the orchestrator (worktrees, queue, review, gate, CI); run the module's tests with scripts/heavy-run.sh ./gradlew ... instead"
            fi
            # cd / pushd must stay inside the worktree.
            while IFS= read -r seg; do
                # Split into words without pathname expansion (`cd *` must stay the word `*`).
                read -r -a words <<< "$seg"
                [ "${words[0]:-}" = cd ] || [ "${words[0]:-}" = pushd ] || continue
                p="${words[1]:-}"
                case "$p" in
                    '' | - | '~'* | *'$'* | *'`'* | *'*'* | *'?'* | *'['* | .. | ../* | */.. | */../*) deny "cd '$p' leaves the worktree or cannot be read" ;;
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
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null TM_WORKTREE_DIR="$tmp/wts" TM_GUARD_LOG="$tmp/guard.log"
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
    expect "an alias that stands for the push" 2 "$wt" Bash "$(bash_in 'git -c alias.p=push p origin HEAD')" "under git's name"
    expect "git -c with another setting" 2 "$wt" Bash "$(bash_in 'git -c core.editor=true commit')"
    expect "a Bash command that names local.properties" 2 "$wt" Bash "$(bash_in 'cat local.properties')" "secrets file"
    expect "a Bash command that names the iOS secrets config" 2 "$wt" Bash "$(bash_in 'sed -n 1p iosApp/TrailMetrics/Secrets.xcconfig')" "secrets file"
    expect "a Bash command that names a .env file" 2 "$wt" Bash "$(bash_in 'cat app/.env.local')" "secrets file"
    expect "a Bash command that names an environment word is not a secrets file" 0 "$wt" Bash "$(bash_in 'echo environment env')"
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
    expect "cd to a glob" 2 "$wt" Bash "$(bash_in 'cd * && ls')" "cannot be read"
    expect "cd to a variable" 2 "$wt" Bash "$(bash_in 'cd $HOME && ls')"
    expect "cd ~" 2 "$wt" Bash "$(bash_in 'cd ~ && ls')"
    expect "a command in a subdirectory of the worktree" 0 "$wt/src" Bash "$(bash_in 'ls')"
    expect "an empty Bash command" 0 "$wt" Bash '{}'
    expect "a tool the guard does not judge" 0 "$wt" WebSearch '{}'

    # From the main clone (a subagent's cwd, always): by what the call names.
    expect "main clone: Read of any file is allowed" 0 "$repo" Read "$(file_in "$repo/src/a.txt")"
    expect "main clone: Read of the task file is allowed" 0 "$repo" Read "$(file_in "$tmp/wts/impl.task.md")"
    expect "main clone: Read of a secrets file" 2 "$repo" Read "$(file_in "$repo/local.properties")" "secrets file"
    expect "main clone: Grep" 0 "$repo" Grep "$(jq -n '{pattern: "one"}')"
    expect "main clone: Read of a file outside the clone" 2 "$repo" Read "$(file_in "/etc/hosts")" "outside the main clone"
    expect "main clone: Read of a relative path" 0 "$repo" Read "$(file_in "src/a.txt")"
    expect "main clone: Read of a relative path that leaves the clone" 2 "$repo" Read "$(file_in "../../etc/hosts")" "'..' component"
    expect "main clone: Grep with a relative path that leaves the clone" 2 "$repo" Grep "$(jq -n '{pattern: "x", path: "../.."}')" "'..' component"
    expect "main clone: Glob of a relative pattern that leaves the clone" 2 "$repo" Glob "$(jq -n '{pattern: "../*"}')" "'..' component"
    expect "main clone: Read with a '..' component" 2 "$repo" Read "$(file_in "$repo/src/../../x")" "'..' component"
    expect "main clone: Grep with a path outside the clone" 2 "$repo" Grep "$(jq -n '{pattern: "x", path: "/etc"}')" "outside the main clone"
    expect "main clone: Grep with a path inside the clone" 0 "$repo" Grep "$(jq -n --arg p "$repo/src" '{pattern: "one", path: $p}')"
    expect "main clone: a Grep pattern that looks like a path is only a pattern" 0 "$repo" Grep "$(jq -n --arg p "$repo/src" '{pattern: "/etc/passwd", path: $p}')"
    expect "main clone: Glob of a pattern outside the clone" 2 "$repo" Glob "$(jq -n '{pattern: "/etc/*"}')" "outside the main clone"
    expect "main clone: Glob of a relative pattern" 0 "$repo" Glob "$(jq -n '{pattern: "src/**/*.kt"}')"
    expect "main clone: Grep that names a secrets file" 2 "$repo" Grep "$(jq -n '{pattern: "KEY", glob: "**/Secrets.xcconfig"}')" "secrets file"
    expect "main clone: Write to an allowed path of a worktree" 0 "$repo" Write "$(file_in "$wt/src/deep/new.kt")"
    expect "main clone: Write to a path that is not allowed" 2 "$repo" Write "$(file_in "$wt/docs/b.txt")" "not one of the allowed paths"
    expect "main clone: Write to the main clone itself" 2 "$repo" Write "$(file_in "$repo/src/x")" "not inside a worktree"
    expect "main clone: Write of the task file" 2 "$repo" Write "$(file_in "$tmp/wts/impl.task.md")" "not inside a worktree"
    expect "main clone: Write with a relative path" 2 "$repo" Write "$(file_in "src/x")" "not an absolute path"
    expect "main clone: Write into a worktree without a record" 2 "$repo" Write "$(file_in "$tmp/plain/src/x")" "not inside a worktree"
    expect "main clone: Write with a '..' component" 2 "$repo" Write "$(file_in "$wt/src/../docs/b.txt")" "'..' component"
    expect "main clone: Bash that starts with cd into the worktree" 0 "$repo" Bash "$(bash_in "cd $wt")"
    expect "main clone: cd, then pwd and git" 0 "$repo" Bash "$(bash_in "cd $wt && pwd && git rev-parse --abbrev-ref HEAD")"
    expect "main clone: cd, then a refused command" 2 "$repo" Bash "$(bash_in "cd $wt && gh pr list")" "orchestrator's"
    expect "main clone: cd, then a command that names a secrets file" 2 "$repo" Bash "$(bash_in "cd $wt && cat local.properties")" "secrets file"
    expect "main clone: cd into a subdirectory of the worktree" 2 "$repo" Bash "$(bash_in "cd $wt/src && ls")" "not the root of a worktree"
    expect "main clone: cd with a relative path" 2 "$repo" Bash "$(bash_in "cd .claude/worktrees/impl")" "not an absolute path"
    expect "main clone: cd somewhere else" 2 "$repo" Bash "$(bash_in 'cd /tmp && ls')" "not one of the worktrees"
    expect "main clone: a command that does not start with cd" 2 "$repo" Bash "$(bash_in "ls && cd $wt")" "begin every Bash command with cd"
    expect "main clone: cd to a variable" 2 "$repo" Bash "$(bash_in 'cd $HOME')"
    expect "main clone: cd to a glob" 2 "$repo" Bash "$(bash_in 'cd *')"
    expect "main clone: cd to a worktree outside the folder" 2 "$repo" Bash "$(bash_in "cd $tmp/plain")" "not one of the worktrees"
    expect "main clone: another tool" 2 "$repo" WebSearch '{}' "begin every Bash command with cd"
    expect "a worktree without a record is refused" 2 "$tmp/plain" Write "$(file_in "$tmp/plain/src/x")" "tm-subagent record"
    expect "a directory outside git is refused" 2 "$other" Bash "$(bash_in 'ls')" "not inside a git work tree"

    # The guard log: what the hook received and every block, readable afterwards.
    local tab last
    tab="$(printf '\t')"
    jq -n --arg cwd "$wt" --arg p "$wt/src/a.txt" '{tool_name: "Read", tool_input: {file_path: $p}, cwd: $cwd, agent_id: "agent-42", agent_type: "implementer"}' | bash "${BASH_SOURCE[0]}" 2>/dev/null
    if grep -Eq "ALLOW${tab}Read${tab}agent-42${tab}implementer${tab}agent_id,agent_type,cwd,tool_input,tool_name${tab}$wt${tab}-${tab}-$" "$tmp/guard.log"; then echo "ok   log: an allowed call records the agent id, type and input keys"; else
        echo "FAIL log: no line with agent-42 and the keys" >&2; tail -n 3 "$tmp/guard.log" >&2; fails=$((fails + 1)); fi
    if grep -Eq "ALLOW${tab}Read${tab}-${tab}-${tab}cwd,tool_input,tool_name${tab}" "$tmp/guard.log"; then echo "ok   log: an input without agent_id logs a dash and its keys"; else
        echo "FAIL log: no dash line for an input without agent_id" >&2; tail -n 3 "$tmp/guard.log" >&2; fails=$((fails + 1)); fi
    expect "a blocked call for the log" 2 "$wt" Bash "$(bash_in 'git remote add x y')" "remotes"
    if grep -Eq "BLOCK${tab}Bash${tab}.*${tab}a git command that pushes.*${tab}git remote add x y$" "$tmp/guard.log"; then echo "ok   log: a block records its reason and the command"; else
        echo "FAIL log: no BLOCK line with reason and command" >&2; tail -n 3 "$tmp/guard.log" >&2; fails=$((fails + 1)); fi
    last="$(bash "${BASH_SOURCE[0]}" --log 2)"
    if [ "$(printf '%s\n' "$last" | wc -l | tr -d ' ')" = 2 ] && printf '%s' "$last" | grep -q 'BLOCK'; then echo "ok   log: --log prints the last lines"; else
        echo "FAIL log: --log 2" >&2; printf '%s\n' "$last" >&2; fails=$((fails + 1)); fi
    expect "a blocked secrets command for the log" 2 "$wt" Bash "$(bash_in 'echo TOKEN=abc123 > local.properties')" "secrets file"
    if grep -q "BLOCK.*(not logged: it names a secrets file)" "$tmp/guard.log" && ! grep -q 'abc123' "$tmp/guard.log"; then echo "ok   log: a secrets block does not log the command text"; else
        echo "FAIL log: the secrets block logged the command or no line" >&2; tail -n 2 "$tmp/guard.log" >&2; fails=$((fails + 1)); fi
    # An unwritable log changes no decision.
    TM_GUARD_LOG=/dev/null/x/guard.log expect "an unwritable log: a blocked call is still blocked" 2 "$wt" Bash "$(bash_in 'git remote add x y')" "remotes"
    TM_GUARD_LOG=/dev/null/x/guard.log expect "an unwritable log: a normal read is still allowed" 0 "$wt" Read "$(file_in "$wt/src/a.txt")"

    if [ "$fails" -eq 0 ]; then echo "guard.sh self-test: all passed"; else echo "guard.sh self-test: $fails failed" >&2; fi
    [ "$fails" -eq 0 ]
}

case "${1:-}" in
    --log)
        [ $# -le 2 ] || { echo "usage: scripts/subagent/guard.sh --log [<n>]" >&2; exit 2; }
        n="${2:-40}"; case "$n" in '' | *[!0-9]*) echo "usage: scripts/subagent/guard.sh --log [<n>]" >&2; exit 2 ;; esac
        if [ -f "$GUARD_LOG" ]; then tail -n "$n" "$GUARD_LOG"; else echo "guard: no log yet ($GUARD_LOG)"; fi
        exit 0 ;;
    --self-test) [ $# -eq 1 ] || { echo "usage: scripts/subagent/guard.sh --self-test (a hook otherwise: JSON on stdin)" >&2; exit 2; }; self_test; exit $? ;;
    "") guard ;;
    *) echo "usage: scripts/subagent/guard.sh --self-test (a hook otherwise: JSON on stdin)" >&2; exit 2 ;;
esac
