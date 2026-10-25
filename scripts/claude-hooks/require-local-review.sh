#!/usr/bin/env bash
# Claude Code hook with two jobs, told apart by `.hook_event_name` of the stdin JSON.
#
# PreToolUse (matcher "Bash"): blocks `git push` and `gh pr create` unless a local review of the
# commit that would be pushed is recorded and allows it (scripts/local-review-gate.sh check). The
# pushed ref is resolved to a SHA: no refspec = HEAD, `src:dst` and `src` = src, so
# `git push origin other:branch` needs the review of `other`. `--all`, `--mirror`, `--tags`, a
# ref that does not resolve and a `gh pr create --head owner:branch` block (nothing to resolve).
# A push that only deletes a remote ref pushes no commit and passes. A command that mentions
# `git push` or `gh pr create` where this script finds no such command (`env git push`,
# `bash -c "git push"`, `xargs git push`) is blocked: the pushed ref cannot be resolved there. A
# `cd <dir>` or `pushd <dir>` earlier in the same command moves the directory the refs are resolved
# in; one whose target cannot be read (variable, ~, -, none, a missing directory, or any cd in a
# group or `||` list, or a cd that is not the command word of its segment) blocks a later push or
# PR creation.
#
# The hook also blocks the main session from calling `local-review-gate.sh record`
# or touching the review records through the shell: the records come from the reviewer itself.
#
# SubagentStop (matcher "pr-reviewer"): records the reviewer's final report (the `message` of its
# last SubagentHandback call in `.agent_transcript_path`) with `local-review-gate.sh record`, keyed by the SHA the reviewer was
# started on (the `SHA:` line of its first message, read from `.agent_transcript_path`); the gate
# refuses a report whose REVIEWED_SHA differs. The transcript is read line by line (a line that is
# not valid JSON is skipped) and polled every 0.25 s until the report appears or
# LOCAL_REVIEW_CAPTURE_WAIT_SECONDS (default 10) are over, because the hook can run before the
# handback line is flushed; a wait that ends with no report says the lines read, the type of the last
# parseable line and the time waited, and writes the input's keys and paths to
# ~/agent-workspace/hook-debug (newest 10 kept). It never blocks the subagent (exit 0) and says on
# stderr what it did.
#
# After a reviewer run, `scripts/local-review-gate.sh check <sha>` shows whether its report was
# recorded (the capture reads the transcript format of Claude Code 2.1.310; if a later version
# changes it, nothing is recorded and every push is blocked, which is the safe failure: the hook
# prints why on stderr, and a SubagentStop that records nothing is the first thing to look at).
#
# Wire format: as block-git-push.sh (stdin JSON, command at `.tool_input.command`, session
# directory at `.cwd`; exit 0 = no decision, exit 2 = block with stderr as the reason). Fail
# closed: a PreToolUse input that mentions a push or a PR creation and cannot be read (no jq, no
# gate script) blocks. Without jq it blocks any input that mentions a push, a PR creation or the
# review records.
#
# Limits: a guardrail, not a wall. It reads command text, so a push built by a variable or a
# script is not seen (the push hook block-git-push.sh still needs the gate marker and a verdict
# for HEAD). The agent can still run `local-review-gate.sh disposition` (it supplies text there;
# the gate checks form and count, not truth). The records are guarded against the shell tool and
# the Write/Edit/MultiEdit/NotebookEdit tools; a process the agent starts that writes there
# (a script it wrote and runs) is out of reach of a hook.
#
# BREAK-GLASS (human only): remove this hook's entries from .claude/settings.json. There is
# deliberately no environment-variable or flag bypass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../local-review-gate.sh"
# A segment that has the words git ... push or gh ... pr ... create in order, whatever sits between
# them (global options, option arguments): when its command is not git / gh itself it is a wrapper.
PUSH_OR_PR_RE='(^|[^[:alnum:]_-])(git[[:space:]]([^|]*[[:space:]])?push|gh[[:space:]]([^|]*[[:space:]])?pr[[:space:]]+create)([^[:alnum:]_-]|$)'

# git_in <dir> <args...>
git_in() { local d="$1"; shift; git -C "$d" "$@"; }

# split_segments <text>: simple commands, one per line.
split_segments() { printf '%s\n' "$1" | tr '&|;()`' '\n\n\n\n\n\n'; }

# Print the SHAs a push or PR creation needs reviewed, one per line, or "BLOCK <reason>".
# resolve_commit <dir> <ref>
resolve_commit() {
    local sha
    if sha="$(git_in "$1" rev-parse --verify --quiet "$2^{commit}" 2>/dev/null)"; then
        echo "$sha"
    else
        echo "BLOCK cannot resolve '$2' to a commit, so the review of what would be pushed cannot be checked"
    fi
}

# targets <dir> <command text>: print one line per needed review: a SHA, "BLOCK <reason>", or
# nothing when no push / PR creation is in the command.
targets() {
    local dir="$1" text="$2" segment i k sub word dir2 found=0 cur="$1" cdunknown=0 grouped=0 target
    local -a tokens
    # Backslash-newline continues a command: join the lines before splitting into segments.
    text="${text//\\$'\n'/ }"
    # A cd inside a group, a command substitution or an `||` list does not change the directory of
    # the following segments the way a linear reading says, so it counts as unreadable.
    case "$text" in *[\(\)\`]* | *"||"*) grouped=1 ;; esac
    # A segment that mentions a push or PR creation but whose command is not git / gh (env, bash -c,
    # xargs, sudo, echo "..."): the pushed ref is hidden from this parser, so it is blocked, whatever
    # plain pushes the rest of the command has.
    while IFS= read -r segment; do
        segment="${segment//[\"\']/}" # quotes do not change which command runs
        read -ra tokens <<<"$segment" || true
        i=0
        while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
        printf '%s\n' "$segment" | grep -qE "$PUSH_OR_PR_RE" || continue
        case "${tokens[$i]:-}" in
            git | */git | gh | */gh) ;;
            *)
                echo "BLOCK a push or PR creation inside a wrapper (env, bash -c, xargs, a quoted string) hides the pushed ref from the local review check; use git push / gh pr create as a plain command"
                found=1
                ;;
        esac
    done < <(split_segments "$text")
    while IFS= read -r segment; do
        segment="${segment//[\"\']/}"
        read -ra tokens <<<"$segment" || true
        i=0
        while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
        [ "$i" -lt "${#tokens[@]}" ] || continue
        # A cd that is not the command word of its segment ({ cd x, then cd x, builtin cd x,
        # command cd x) cannot be followed: a later push or PR creation blocks.
        for ((k = 0; k < ${#tokens[@]}; k++)); do
            [ "$k" -ne "$i" ] || continue
            case "${tokens[$k]}" in cd | pushd | popd) cdunknown=1 ;; esac
        done
        dir2="$cur"
        case "${tokens[$i]##*/}" in
            cd | pushd)
                # The refs of the later segments are resolved in the directory this changes to.
                # A target that cannot be read from the text (variable, ~, -, none, a directory that
                # does not exist) makes a later push or PR creation in this command a block.
                i=$((i + 1))
                [ "${tokens[$i]:-}" != -- ] || i=$((i + 1))
                target="${tokens[$i]:-}"
                if [ "$grouped" = 1 ] || [ -z "$target" ] || [[ "$target" == -* ]] || [[ "$target" == *[\$~\`\*\?\[]* ]]; then
                    cdunknown=1
                    continue
                fi
                [ "${target#/}" != "$target" ] || target="$cur/$target"
                if [ -d "$target" ]; then
                    cur="$(cd "$target" && pwd)"
                else
                    cdunknown=1
                fi
                ;;
            popd) cdunknown=1 ;;
            git)
                i=$((i + 1))
                while [ "$i" -lt "${#tokens[@]}" ]; do
                    case "${tokens[$i]}" in
                        -C) dir2="${tokens[$((i + 1))]:-.}"; [ "${dir2#/}" != "$dir2" ] || dir2="$cur/$dir2"; i=$((i + 2)) ;;
                        -c) case "${tokens[$((i + 1))]:-}" in alias.*) echo "BLOCK git -c alias.* is not allowed"; found=1 ;; esac; i=$((i + 2)) ;;
                        --git-dir | --work-tree | --namespace | --config-env | --exec-path | --super-prefix)
                            echo "BLOCK git ${tokens[$i]} <path> changes the repository the push runs in, which this hook cannot follow; run the push from that directory as a plain git push"
                            found=1; i=$((i + 2)) ;;
                        -*) i=$((i + 1)) ;;
                        *) break ;;
                    esac
                done
                [ "$i" -lt "${#tokens[@]}" ] || continue
                sub="${tokens[$i]}"
                i=$((i + 1))
                if [ "$sub" != push ]; then
                    # A configured alias that runs a push is a push.
                    if git_in "$dir2" config --get "alias.$sub" 2>/dev/null | grep -qE '(^|[^[:alnum:]_-])push([^[:alnum:]_-]|$)'; then
                        echo "BLOCK git alias '$sub' runs a push; use git push itself"
                        found=1
                    fi
                    continue
                fi
                found=1
                if [ "$cdunknown" = 1 ]; then
                    echo "BLOCK a cd with a target this hook cannot read comes before this push; run the push in its own command, from the directory it pushes"
                else
                    push_targets "$dir2" "${tokens[@]:$i}"
                fi
                ;;
            gh)
                i=$((i + 1))
                while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" == -* ]]; do
                    case "${tokens[$i]}" in -R | --repo | --hostname) i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
                done
                if [ "${tokens[$i]:-}" = pr ] && [ "${tokens[$((i + 1))]:-}" = create ]; then
                    found=1
                    if [ "$cdunknown" = 1 ]; then
                        echo "BLOCK a cd with a target this hook cannot read comes before this PR creation; run it in its own command, from the directory it belongs to"
                    else
                        pr_targets "$dir2" "${tokens[@]:$((i + 2))}"
                    fi
                elif [ "${tokens[$i]:-}" = api ]; then
                    # A PR created through the API: POST to .../pulls.
                    case " ${tokens[*]:$i} " in
                        *"/pulls "* | *"/pulls?"*)
                            case " ${tokens[*]:$i} " in
                                *" -X POST "* | *" --method POST "* | *" -f "* | *" -F "* | *" --field "* | *" --raw-field "* | *" --input "*)
                                    found=1; echo "BLOCK a pull request created through 'gh api' is not allowed; use gh pr create"
                                    ;;
                            esac
                            ;;
                    esac
                fi
                ;;
        esac
    done < <(split_segments "$text")
}

push_targets() {
    local dir="$1" word remote_seen=0 delete=0 refs=0 src
    shift
    local -a args=("$@") positional=()
    local i=0
    while [ "$i" -lt "${#args[@]}" ]; do
        word="${args[$i]}"
        case "$word" in
            --all | --mirror | --tags | --branches) echo "BLOCK 'git push $word' pushes refs this hook cannot resolve to one reviewed commit; push the branch by name"; return 0 ;;
            --delete | -d) delete=1 ;;
            -o | --push-option | --repo | --receive-pack | --exec) i=$((i + 1)) ;;
            -*) ;;
            *) positional+=("$word") ;;
        esac
        i=$((i + 1))
    done
    # positional[0] is the remote, the rest are refspecs.
    if [ "${#positional[@]}" -le 1 ]; then
        resolve_commit "$dir" HEAD
        return 0
    fi
    for word in "${positional[@]:1}"; do
        refs=1
        word="${word#+}"
        if [ "$delete" = 1 ]; then continue; fi
        if [[ "$word" == *:* ]]; then
            src="${word%%:*}"
            [ -n "$src" ] || continue # ":dst" deletes dst
        else
            src="$word"
        fi
        resolve_commit "$dir" "$src"
    done
    [ "$refs" = 1 ] || resolve_commit "$dir" HEAD
}

pr_targets() {
    local dir="$1" head="" i=0
    shift
    local -a args=("$@")
    while [ "$i" -lt "${#args[@]}" ]; do
        case "${args[$i]}" in
            --head | -H) head="${args[$((i + 1))]:-}"; i=$((i + 1)) ;;
            --head=*) head="${args[$i]#--head=}" ;;
            -H?*) head="${args[$i]#-H}" ;;
        esac
        i=$((i + 1))
    done
    if [ -z "$head" ]; then
        resolve_commit "$dir" HEAD
    elif [[ "$head" == *:* ]]; then
        echo "BLOCK gh pr create --head $head names a branch of another owner; the review of its commit cannot be checked"
    else
        resolve_commit "$dir" "$head"
    fi
}

# Shell commands that would put a report in the records or call record themselves.
touches_records() {
    local dir="${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}"
    printf '%s\n' "$1" | grep -qE 'local-review-gate(\.sh)?[[:space:]]+record|local-reviews|LOCAL_REVIEWS_DIR' && return 0
    case "$1" in *"$dir"*) return 0 ;; esac
    return 1
}

handle_pre_tool_use() {
    local input="$1" command cwd root target reason out rc=0 tool fpath
    tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
    case "$tool" in
        Write | Edit | MultiEdit | NotebookEdit)
            # The file tools must not write the records either.
            fpath="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
            if touches_records "$fpath"; then
                echo "Blocked: the local review records are written by the reviewer's own report only (SubagentStop hook), not by file tools." >&2
                return 2
            fi
            return 0
            ;;
    esac
    command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    if touches_records "$command"; then
        echo "Blocked: the local review records are written by the reviewer's own report only (SubagentStop hook). Do not call 'local-review-gate.sh record' or touch the local-reviews directory; run the pr-reviewer instead. 'local-review-gate.sh disposition' and 'check' are allowed." >&2
        # disposition/check are the allowed uses of the script; they do not mention the directory.
        return 2
    fi
    # targets ends its output with END; a run that died before that (unbound variable, bash 3.2
    # quirk) is a block, not "no push in this command".
    out="$(targets "${cwd:-$PWD}" "$command"; echo END)" || out=""
    if [ "$(printf '%s\n' "$out" | tail -n1)" != END ]; then
        echo "Blocked: could not parse this command to check the local review (internal error in $(basename "${BASH_SOURCE[0]}"))." >&2
        return 2
    fi
    out="$(printf '%s\n' "$out" | sed '$d')"
    [ -n "$out" ] || return 0
    root="$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null)" || {
        echo "Blocked: this command pushes or opens a PR but the session directory is not a git work tree, so the local review cannot be checked." >&2
        return 2
    }
    [ -x "$GATE" ] || { echo "Blocked: $GATE is missing or not executable, so the local review cannot be checked." >&2; return 2; }
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        if [[ "$target" == BLOCK\ * ]]; then
            echo "Blocked: ${target#BLOCK }." >&2
            return 2
        fi
        if ! reason="$(cd "$root" && "$GATE" check "$target" 2>&1 >/dev/null)"; then
            {
                echo "$reason"
                echo "No push and no PR until the local review of this exact commit allows it (tm-pr-workflow, \"Push and PR\"): review the final commit, fix, review again, write the dispositions, then push. Do not work around this hook."
            } >&2
            return 2
        fi
    done <<<"$out"
    return 0
}

# The transcript is read line by line: a line that is not valid JSON (a half-written last line) is
# skipped, so it cannot empty the result.
transcript_entries() { jq -R 'fromjson? // empty' "$1" 2>/dev/null || true; }

transcript_report() {
    transcript_entries "$1" | jq -rs '
        ([.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "SubagentHandback") | .input.message] | last)
        // ([.[] | select(.type == "assistant") | .message.content | if type == "array" then map(select(.type == "text") | .text) | join("") else . end | select(type == "string" and test("^(NO_)?VERDICT: "))] | last)
        // empty' 2>/dev/null || true
}

# The hook input (keys and paths, never the report text) for a capture that found no report, in
# ~/agent-workspace/hook-debug (not the records directory); the newest 10 files are kept.
write_capture_debug() { # write_capture_debug <input> <transcript> <lines> <last type> <waited>
    local dir="$HOME/agent-workspace/hook-debug" f
    f="$dir/subagent-stop-$(date +%Y%m%dT%H%M%S)-$$.json"
    {
        mkdir -p "$dir" \
            && printf '%s' "$1" | jq --arg lines "$3" --arg last "$4" --arg waited "$5" \
                '{keys: keys, paths: (to_entries | map(select(.key | test("path|cwd|dir"; "i"))) | from_entries), transcript_lines: ($lines | tonumber? // 0), last_parseable_type: $last, waited_seconds: ($waited | tonumber? // 0)}' > "$f" \
            && { ls -1t "$dir"/subagent-stop-*.json 2>/dev/null | tail -n +11 | while IFS= read -r old; do rm -f -- "$old"; done; }
    } 2>/dev/null || true
}

handle_subagent_stop() {
    local input="$1" agent msg transcript cwd root sha
    agent="$(printf '%s' "$input" | jq -r '.agent_type // empty')"
    [ "$agent" = pr-reviewer ] || return 0
    transcript="$(printf '%s' "$input" | jq -r '.agent_transcript_path // empty')"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
    if [ ! -f "$transcript" ]; then
        echo "local review not recorded: the reviewer's transcript is missing" >&2
        return 0
    fi
    # Verified on Claude Code 2.1.310 (2026-10-25): the SubagentStop input has no
    # `last_assistant_message` for a reviewer that hands its report back; the report is the `message`
    # input of its last SubagentHandback tool call in the transcript (JSONL). A final plain-text
    # message that starts like a report is used when that call is absent. The hook can run before
    # the handback line is flushed, so it polls the transcript until a report appears or the wait
    # (LOCAL_REVIEW_CAPTURE_WAIT_SECONDS, default 10; it only sets the wait) is over.
    local wait_s polls=0 max_polls waited lines last_type
    wait_s="${LOCAL_REVIEW_CAPTURE_WAIT_SECONDS:-10}"
    case "$wait_s" in ''|*[!0-9.]*|*.*.*) wait_s=10 ;; esac
    max_polls="$(awk -v w="$wait_s" 'BEGIN { printf "%d", w * 4 }')"
    msg="$(transcript_report "$transcript")"
    while [ -z "$msg" ] && [ "$polls" -lt "$max_polls" ]; do
        sleep 0.25
        polls=$((polls + 1))
        msg="$(transcript_report "$transcript")"
    done
    if [ -z "$msg" ]; then
        waited="$(awk -v n="$polls" 'BEGIN { printf "%.2f", n * 0.25 }')"
        lines="$(grep -c '' "$transcript" 2>/dev/null || true)"
        last_type="$(transcript_entries "$transcript" | jq -r '.type // "none"' 2>/dev/null | tail -n 1)"
        echo "local review: no report in the reviewer's transcript after waiting ${waited}s (lines read: ${lines:-0}, type of the last parseable line: ${last_type:-none})" >&2
        write_capture_debug "$input" "$transcript" "${lines:-0}" "${last_type:-none}" "$waited"
        msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"
    fi
    if [ -z "$msg" ]; then
        echo "local review not recorded: no final report in the reviewer's transcript" >&2
        return 0
    fi
    # The SHA the reviewer was started on: the `SHA: <full sha>` line of the first user message
    # of its transcript (the session's four inputs), before anything the reviewer read.
    sha="$(transcript_entries "$transcript" | jq -rs '[.[] | select(.type == "user")][0] | .message.content | if type == "array" then map(.text // "") | join("\n") else . end // empty' 2>/dev/null \
        | grep -E -m1 '^SHA: ([0-9a-f]{40}|[0-9a-f]{64})$' | sed 's/^SHA: //' || true)"
    if [ -z "$sha" ]; then
        echo "local review not recorded: no 'SHA: <full sha>' line in the reviewer's first message" >&2
        return 0
    fi
    root="$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null)" || { echo "local review not recorded: not a git work tree" >&2; return 0; }
    printf '%s\n' "$msg" | (cd "$root" && "$GATE" record "$sha") >&2 || echo "local review not recorded (see the reason above)" >&2
    return 0
}

self_test() {
    local hook tmp fails=0 repo sha parent other rc name want
    hook="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' RETURN
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp" LOCAL_REVIEWS_DIR="$tmp/reviews"
    repo="$tmp/repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name t
    git -C "$repo" commit -q --allow-empty -m one
    parent="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" switch -q -c other
    git -C "$repo" commit -q --allow-empty -m side
    git -C "$repo" switch -q main
    git -C "$repo" commit -q --allow-empty -m two
    sha="$(git -C "$repo" rev-parse HEAD)"
    other="$(git -C "$repo" rev-parse other)"
    git -C "$repo" config alias.sneak 'push origin HEAD'
    # A second checkout (stands for a linked worktree or another repo) with its own commit.
    local repo2 sha2
    repo2="$tmp/repo2"
    git init -q -b main "$repo2"
    git -C "$repo2" config user.email t@example.com
    git -C "$repo2" config user.name t
    git -C "$repo2" commit -q --allow-empty -m "other checkout"
    sha2="$(git -C "$repo2" rev-parse HEAD)"

    review() { # review <sha> <verdict> [extra report lines...]
        local s="$1" v="$2"
        shift 2
        { printf 'VERDICT: %s\nREVIEWED_SHA: %s\nPROTECTED: none\n' "$v" "$s"; printf '%s\n' "$@"; } | (cd "$repo" && "$GATE" record "$s") >/dev/null 2>&1 || true
    }
    review_in() { # review_in <dir> <sha> (an APPROVE report recorded from that checkout)
        printf 'VERDICT: APPROVE\nREVIEWED_SHA: %s\nPROTECTED: none\nNo findings.\n' "$2" | (cd "$1" && "$GATE" record "$2") >/dev/null 2>&1 || true
    }
    # expect <name> <want exit> <command>
    expect() {
        name="$1"; want="$2"; rc=0
        jq -n --arg c "$3" --arg d "$repo" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
            | bash "$hook" >/dev/null 2>"$tmp/err" || rc=$?
        if [ "$rc" = "$want" ]; then echo "ok   $name (exit $rc)"; else echo "FAIL $name: expected exit $want, got $rc: $(head -c 300 "$tmp/err")" >&2; fails=$((fails + 1)); fi
    }

    expect "non-push command passes" 0 "git status"
    expect "a mention of git push is blocked (wrapped push)" 2 "echo git push"
    expect "push with no review blocks" 2 "git push -u origin main"
    expect "gh pr create with no review blocks" 2 "gh pr create --base main --body-file b.md"
    expect "wrapped push blocks" 2 "bash -c 'git push'"
    expect "git alias that pushes blocks" 2 "git sneak"
    expect "git -c alias blocks" 2 "git -c alias.p=push p"
    # The shared corpus, in the state "nothing allowed yet" (no review recorded): `push` lines must
    # block, `nopush` lines must pass. block-git-push.sh runs the same file.
    local line kind cmd cn=0
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        kind="${line%% *}"; cmd="${line#* }"; cn=$((cn + 1))
        if [ "$kind" = push ]; then expect "corpus push: $cmd" 2 "$cmd"; else expect "corpus nopush: $cmd" 0 "$cmd"; fi
    done < "$SCRIPT_DIR/push-commands-fixtures/corpus"
    [ "$cn" -gt 0 ] || { echo "FAIL the push-commands corpus is empty" >&2; fails=$((fails + 1)); }
    review "$parent" APPROVE
    expect "review of the parent commit does not allow the push" 2 "git push"
    review "$sha" CHANGES "1. [blocking] a.kt (f): item 2: defect; fix"
    expect "CHANGES blocks" 2 "git push"
    review "$sha" APPROVE
    expect "APPROVE allows git push" 0 "git push -u origin main"
    expect "APPROVE allows git -C . push" 0 "git -C . push"
    expect "APPROVE allows gh pr create" 0 "gh pr create --base main --body-file b.md"
    expect "APPROVE allows a chained push" 0 "git fetch && git push origin HEAD"
    expect "push of another branch needs its review" 2 "git push origin other:branch"
    # A push the parser does not see as a command is blocked, even though HEAD has an allowing review.
    expect "bash -c push is blocked while HEAD is reviewed" 2 "bash -c 'git push'"
    expect "env git push of an unreviewed ref is blocked while HEAD is reviewed" 2 "env git push origin other:x"
    expect "xargs push is blocked while HEAD is reviewed" 2 "echo origin | xargs git push"
    expect "bash -c push with a git global option blocks" 2 "bash -c 'git --no-pager push origin other:x'"
    expect "env git --git-dir=x push blocks" 2 "env git --git-dir=x push origin other:x"
    expect "sudo gh with options before pr create blocks" 2 "sudo gh -R o/r pr create --head other"
    expect "git --git-dir with a separate argument blocks" 2 "git --git-dir x push origin other:x"
    expect "git --no-pager push is a plain push and is checked" 0 "git --no-pager push origin HEAD"
    expect "a refspec on a continuation line is resolved" 2 "$(printf 'git push origin \\\nother:x')"
    expect "a continuation line with HEAD is a plain push" 0 "$(printf 'git push origin \\\nHEAD')"
    expect "a quoted command word is still a push" 2 '"git" push origin other:x'
    expect "a quoted subcommand is still a push" 2 "git 'push' origin other:x"
    expect "a split quoted command word is still a push" 2 'g"i"t push origin other:x'
    expect "a plain push followed by a wrapped push to an unreviewed ref blocks" 2 "git push && env git push origin other:x"
    expect "a plain push then bash -c push blocks" 2 "git push; bash -c 'git push origin other:x'"
    expect "a wrapped push then a plain push blocks" 2 "env git push origin other:x && git push"
    expect "a mention of gh pr create is blocked while HEAD is reviewed" 2 "env gh pr create --head other"
    # cd / pushd change the directory the refs are resolved in.
    expect "cd to another checkout: its HEAD has no review, blocked" 2 "cd $repo2 && git push"
    expect "cd to a relative checkout: blocked without its review" 2 "cd ../repo2 && git push"
    expect "cd then git -C . resolves in the new directory: blocked without its review" 2 "cd $repo2 && git -C . push"
    expect "cd then a relative git -C resolves against the new directory" 2 "cd $tmp && git -C repo2 push"
    expect "git -C with an absolute path" 2 "git -C $repo2 push"
    expect "pushd to another checkout: blocked without its review" 2 "pushd $repo2 && git push"
    expect "cd to a variable target blocks" 2 'cd "$X" && git push'
    expect "cd ~ blocks" 2 "cd ~ && git push"
    expect "cd - blocks" 2 "cd - && git push"
    expect "cd with no argument blocks" 2 "cd && git push"
    expect "cd to a missing directory blocks" 2 "cd $tmp/nosuch && git push"
    expect "cd in a subshell then push blocks" 2 "(cd $repo2); git push"
    expect "cd in braces then push blocks while HEAD is reviewed" 2 "{ cd ../repo2; git push; }"
    expect "cd after then, then push blocks while HEAD is reviewed" 2 "if true; then cd ../repo2; git push; fi"
    expect "builtin cd then push blocks while HEAD is reviewed" 2 "builtin cd ../repo2 && git push"
    expect "command cd then push blocks while HEAD is reviewed" 2 "command cd ../repo2 && git push"
    expect "cd without a push passes" 0 "cd $repo2 && git status"
    expect "cd back to the reviewed checkout allows" 0 "cd $repo2 && cd $repo && git push"
    review_in "$repo2" "$sha2"
    expect "cd to another checkout with its review allows" 0 "cd $repo2 && git push"
    expect "cd in braces then push blocks even with the target's review" 2 "{ cd ../repo2; git push; }"
    expect "cd then git -C . with the review of that directory allows" 0 "cd $repo2 && git -C . push"
    expect "cd then a relative git -C with the review allows" 0 "cd $tmp && git -C repo2 push"
    expect "git -C with an absolute path with its review allows" 0 "git -C $repo2 push"
    expect "cd to a relative checkout with its review allows" 0 "cd ../repo2 && gh pr create"
    expect "push of a ref that does not resolve blocks" 2 "git push origin nosuch:branch"
    expect "push --all blocks" 2 "git push --all origin"
    expect "push --tags blocks" 2 "git push --tags"
    expect "deleting a remote branch pushes no commit" 0 "git push origin --delete old"
    expect "deleting by :dst pushes no commit" 0 "git push origin :old"
    expect "gh pr create --head other needs its review" 2 "gh pr create --head other"
    expect "gh pr create --head owner:branch blocks" 2 "gh pr create --head someone:branch"
    expect "gh api POST pulls blocks" 2 "gh api repos/o/r/pulls -f title=t"
    review "$other" APPROVE
    expect "push of another branch with its review allowed" 0 "git push origin other:branch"
    expect "calling record from the shell blocks" 2 "scripts/local-review-gate.sh record $sha"
    expect "touching the records directory blocks" 2 "echo x > $tmp/reviews/$sha/report"
    for tool in Write Edit MultiEdit NotebookEdit; do
        rc=0
        jq -n --arg t "$tool" --arg f "$tmp/reviews/$sha/report" --arg d "$repo" '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{file_path:$f,notebook_path:$f},cwd:$d}' \
            | bash "$hook" >/dev/null 2>&1 || rc=$?
        if [ "$rc" = 2 ]; then echo "ok   $tool of a record blocks (exit 2)"; else echo "FAIL $tool of a record: expected exit 2, got $rc" >&2; fails=$((fails + 1)); fi
    done
    rc=0
    jq -n --arg f "$repo/README.md" --arg d "$repo" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f},cwd:$d}' | bash "$hook" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then echo "ok   Write of another file passes (exit 0)"; else echo "FAIL Write of another file: got $rc" >&2; fails=$((fails + 1)); fi
    review "$sha" ESCALATE_TO_HUMAN "1. [important] a.kt (f): item 13: suspicion; fix"
    expect "important without disposition blocks" 2 "git push"
    (cd "$repo" && "$GATE" disposition "$sha" "board record some-slug") >/dev/null 2>&1
    expect "important with disposition allows" 0 "git push"
    git -C "$repo" commit -q --allow-empty -m three
    expect "a new commit needs a new review" 2 "git push"

    # Without jq the input cannot be read: a push, a PR creation or the records directory blocks.
    local nojq="$tmp/nojq" t
    mkdir -p "$nojq"
    for t in dirname basename grep cat sed tr head tail; do ln -sf "$(command -v "$t")" "$nojq/$t"; done
    nojq_expect() { # nojq_expect <name> <want exit> <json>
        name="$1"; want="$2"; rc=0
        printf '%s' "$3" | PATH="$nojq" "$BASH" "$hook" >/dev/null 2>"$tmp/err" || rc=$?
        if [ "$rc" = "$want" ]; then echo "ok   $name (exit $rc)"; else echo "FAIL $name: expected exit $want, got $rc: $(head -c 300 "$tmp/err")" >&2; fails=$((fails + 1)); fi
    }
    nojq_expect "no jq: a Write naming the records directory blocks" 2 "$(jq -n --arg f "$tmp/reviews/$sha/report" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f}}')"
    nojq_expect "no jq: a command naming the records directory blocks" 2 "$(jq -n --arg c "cat $tmp/reviews/$sha/report" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
    nojq_expect "no jq: a push blocks" 2 "$(jq -n '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git push"}}')"
    nojq_expect "no jq: a PR creation blocks" 2 "$(jq -n '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"gh pr create"}}')"
    nojq_expect "no jq: an unrelated command passes" 0 "$(jq -n '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git status"}}')"
    nojq_expect "no jq: a Write of another file passes" 0 "$(jq -n --arg f "$repo/README.md" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f}}')"

    # SubagentStop: capture the reviewer's own report. The transcript has the format of Claude Code
    # 2.1.310: the first user entry holds the session's inputs, the report is the `message` input of
    # the last SubagentHandback tool call.
    local tr="$tmp/transcript.jsonl" head3 head4 head5
    head3="$(git -C "$repo" rev-parse HEAD)"
    capture() { # capture <agent_type> <run-on sha> <report>
        jq -nc --arg s "$2" --arg m "$3" \
            '{type:"user",message:{role:"user",content:("SHA: " + $s + "\nBASE: x\nINPUT_DIR: /x\nTASK: t")}},
             {type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:$m}}]}}' >"$tr"
        jq -n --arg t "$1" --arg p "$tr" --arg d "$repo" \
            '{hook_event_name:"SubagentStop",agent_type:$t,agent_transcript_path:$p,cwd:$d}' | bash "$hook" >/dev/null 2>"$tmp/err"
    }
    report() { printf 'VERDICT: APPROVE\nREVIEWED_SHA: %s\nPROTECTED: none\nNo findings.' "$1"; }
    capture pr-reviewer "$head3" "$(report "$head3")" || fails=$((fails + 1))
    expect "reviewer report captured by SubagentStop allows the push" 0 "git push"
    git -C "$repo" commit -q --allow-empty -m four
    head4="$(git -C "$repo" rev-parse HEAD)"
    capture pr-reviewer "$head3" "$(report "$head4")" || fails=$((fails + 1))
    expect "forged REVIEWED_SHA (reviewer ran on another commit) is not recorded" 2 "git push"
    capture pr-reviewer "$head4" "NO_VERDICT: TREE_NOT_CLEAN" || fails=$((fails + 1))
    expect "NO_VERDICT is not recorded" 2 "git push"
    capture general-purpose "$head4" "$(report "$head4")" || fails=$((fails + 1))
    expect "another agent type is not recorded" 2 "git push"
    capture pr-reviewer "$head4" "$(report "$head4")" || fails=$((fails + 1))
    expect "reviewer report on the new commit allows the push" 0 "git push"
    # A reviewer that ends with plain text instead of a handback call.
    git -C "$repo" commit -q --allow-empty -m five
    head5="$(git -C "$repo" rev-parse HEAD)"
    jq -nc --arg s "$head5" --arg m "$(report "$head5")" \
        '{type:"user",message:{role:"user",content:("SHA: " + $s + "\nBASE: x")}},{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$m}]}}' >"$tr"
    jq -n --arg p "$tr" --arg d "$repo" '{hook_event_name:"SubagentStop",agent_type:"pr-reviewer",agent_transcript_path:$p,cwd:$d}' | bash "$hook" >/dev/null 2>&1 || fails=$((fails + 1))
    expect "a plain final message is recorded too" 0 "git push"

    # The report may reach the transcript after the hook starts (SubagentStop can run before the
    # handback line is flushed). Each case runs on a new commit so an earlier record cannot allow it.
    local pre hb cut t0 elapsed n dbg wait_cfg
    pre="$tmp/pre.jsonl"
    new_head() { git -C "$repo" commit -q --allow-empty -m "$1"; git -C "$repo" rev-parse HEAD; }
    stop_input() { jq -n --arg p "$tr" --arg d "$repo" '{hook_event_name:"SubagentStop",agent_type:"pr-reviewer",agent_transcript_path:$p,cwd:$d,session_id:"s1",last_assistant_message:null}'; }
    prepare() { # prepare <sha>: the transcript so far (the first user entry and a tool call), no report; hb = the handback line
        jq -nc --arg s "$1" '{type:"user",message:{role:"user",content:("SHA: " + $s + "\nBASE: x\nINPUT_DIR: /x\nTASK: t")}},
            {type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Read",input:{file_path:"/x"}}]}}' >"$tr"
        hb="$(jq -nc --arg m "$(report "$1")" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:$m}}]}}')"
    }
    # 1. the handback line is appended 1.5 s after the hook starts
    head5="$(new_head six)"; prepare "$head5"
    ( sleep 1.5; printf '%s\n' "$hb" >>"$tr" ) &
    t0=$SECONDS
    stop_input | LOCAL_REVIEW_CAPTURE_WAIT_SECONDS=8 bash "$hook" >/dev/null 2>"$tmp/err" || fails=$((fails + 1))
    wait
    expect "a handback appended 1.5 s after the hook starts is recorded" 0 "git push"
    # 2. the file ends in a half-written line that is completed after 1 s
    head5="$(new_head seven)"; prepare "$head5"
    cut=$((${#hb} / 2))
    printf '%s' "${hb:0:cut}" >>"$tr"
    ( sleep 1; printf '%s\n' "${hb:cut}" >>"$tr" ) &
    stop_input | LOCAL_REVIEW_CAPTURE_WAIT_SECONDS=8 bash "$hook" >/dev/null 2>"$tmp/err" || fails=$((fails + 1))
    wait
    expect "a half-written last line that is completed later is recorded" 0 "git push"
    # 3. the report never arrives: the hook waits the configured time, exits 0, records nothing, says the numbers
    head5="$(new_head eight)"; prepare "$head5"
    mkdir -p "$tmp/agent-workspace/hook-debug"
    for n in 1 2 3 4 5 6 7 8 9 10 11 12; do echo '{}' > "$tmp/agent-workspace/hook-debug/subagent-stop-2000010${n}T000000-$n.json"; touch -t "20000101000$((n % 10))" "$tmp/agent-workspace/hook-debug/subagent-stop-2000010${n}T000000-$n.json"; done
    rc=0; t0=$SECONDS
    stop_input | LOCAL_REVIEW_CAPTURE_WAIT_SECONDS=2 bash "$hook" >/dev/null 2>"$tmp/err" || rc=$?
    elapsed=$((SECONDS - t0))
    if [ "$rc" = 0 ] && [ "$elapsed" -ge 2 ] && [ "$elapsed" -lt 9 ] && grep -q 'after waiting 2' "$tmp/err" && grep -q 'lines read: 2' "$tmp/err" && grep -q 'type of the last parseable line: assistant' "$tmp/err"; then
        echo "ok   a report that never arrives: waited ${elapsed}s, exit 0, numbers on stderr"
    else
        echo "FAIL a report that never arrives: rc=$rc elapsed=${elapsed}s stderr: $(head -c 300 "$tmp/err")" >&2; fails=$((fails + 1))
    fi
    expect "a report that never arrives records nothing" 2 "git push"
    dbg="$(ls -1 "$tmp"/agent-workspace/hook-debug/subagent-stop-*.json 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$dbg" = 10 ] && ! grep -rq 'VERDICT' "$tmp/agent-workspace/hook-debug" && grep -lq '"keys"' "$tmp"/agent-workspace/hook-debug/*.json; then
        echo "ok   the debug file is written without report text and the newest 10 are kept"
    else
        echo "FAIL the debug file: $dbg files kept, expected 10 with keys and no report text" >&2; fails=$((fails + 1))
    fi
    # 4. the report is already there (and the file ends in a half-written line): no waiting
    head5="$(new_head nine)"; prepare "$head5"
    printf '%s\n%s' "$hb" '{"type":"assistant","mess' >>"$tr"
    wait_cfg=8
    t0=$SECONDS
    stop_input | LOCAL_REVIEW_CAPTURE_WAIT_SECONDS=$wait_cfg bash "$hook" >/dev/null 2>"$tmp/err" || fails=$((fails + 1))
    elapsed=$((SECONDS - t0))
    if [ "$elapsed" -lt "$wait_cfg" ]; then echo "ok   a report already there is read without waiting (${elapsed}s)"; else echo "FAIL a report already there waited ${elapsed}s" >&2; fails=$((fails + 1)); fi
    expect "a report already there (bad last line skipped) is recorded" 0 "git push"

    if [ "$fails" -ne 0 ]; then
        echo "require-local-review.sh self-test: $fails failed" >&2
        return 1
    fi
    echo "require-local-review.sh self-test: all passed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
    # Without jq the input cannot be read: block anything that mentions a push, a PR creation or the
    # review records (any tool, so the file-tool guard holds too).
    if printf '%s' "$INPUT" | grep -qE 'git.*push|gh.*pr.*create|local-reviews' \
        || printf '%s' "$INPUT" | grep -qF -e "${LOCAL_REVIEWS_DIR:-$HOME/agent-workspace/local-reviews}"; then
        echo "Blocked: jq is needed to check the local review before a push or PR, or a write to the review records, and is not installed." >&2
        exit 2
    fi
    exit 0
fi

EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
case "$EVENT" in
    SubagentStop) handle_subagent_stop "$INPUT"; exit 0 ;;
    PreToolUse)
        rc=0
        handle_pre_tool_use "$INPUT" || rc=$?
        exit "$rc"
        ;;
    *) exit 0 ;;
esac
