#!/usr/bin/env bash
# Claude Code hook with two jobs, told apart by `.hook_event_name` of the stdin JSON.
#
# PreToolUse (matcher "Bash"): blocks `git push` and `gh pr create` unless a local review of the
# commit that would be pushed is recorded and allows it (scripts/local-review-gate.sh check). The
# pushed ref is resolved to a SHA: no refspec = HEAD, `src:dst` and `src` = src, so
# `git push origin other:branch` needs the review of `other`. `--all`, `--mirror`, `--tags`, a
# ref that does not resolve and a `gh pr create --head owner:branch` block (nothing to resolve).
# A push that only deletes a remote ref pushes no commit and passes. A command that mentions
# `git push` or `gh pr create` where this script finds no such command (`bash -c "git push"`) needs
# the review of HEAD. It also blocks the main session from calling `local-review-gate.sh record`
# or touching the review records through the shell: the records come from the reviewer itself.
#
# SubagentStop (matcher "pr-reviewer"): records the reviewer's final message
# (`.last_assistant_message`) with `local-review-gate.sh record`, keyed by the SHA the reviewer was
# started on (the `SHA:` line of its first message, read from `.agent_transcript_path`); the gate
# refuses a report whose REVIEWED_SHA differs. It never blocks the subagent (exit 0) and says on
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
# gate script) blocks. Needs jq.
#
# Limits: a guardrail, not a wall. It reads command text, so a push built by a variable or a
# script is not seen (the push hook block-git-push.sh still needs the gate marker and a verdict
# for HEAD). The agent can still run `local-review-gate.sh disposition` (it supplies text there;
# the gate checks form and count, not truth). Anything that writes to the records outside the
# shell tool is out of reach of a hook.
#
# BREAK-GLASS (human only): remove this hook's entries from .claude/settings.json. There is
# deliberately no environment-variable or flag bypass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../local-review-gate.sh"

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
    local dir="$1" text="$2" segment i sub word dir2 found=0
    local -a tokens
    while IFS= read -r segment; do
        read -ra tokens <<<"$segment" || true
        i=0
        while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
        [ "$i" -lt "${#tokens[@]}" ] || continue
        dir2="$dir"
        case "${tokens[$i]##*/}" in
            git)
                i=$((i + 1))
                while [ "$i" -lt "${#tokens[@]}" ]; do
                    case "${tokens[$i]}" in
                        -C) dir2="${tokens[$((i + 1))]:-.}"; [ "${dir2#/}" != "$dir2" ] || dir2="$dir/$dir2"; i=$((i + 2)) ;;
                        -c) case "${tokens[$((i + 1))]:-}" in alias.*) echo "BLOCK git -c alias.* is not allowed"; found=1 ;; esac; i=$((i + 2)) ;;
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
                push_targets "$dir2" "${tokens[@]:$i}"
                ;;
            gh)
                i=$((i + 1))
                while [ "$i" -lt "${#tokens[@]}" ] && [[ "${tokens[$i]}" == -* ]]; do
                    case "${tokens[$i]}" in -R | --repo | --hostname) i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
                done
                if [ "${tokens[$i]:-}" = pr ] && [ "${tokens[$((i + 1))]:-}" = create ]; then
                    found=1
                    pr_targets "$dir2" "${tokens[@]:$((i + 2))}"
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
    # Mentions of a push or PR creation this parser did not see as a command (a wrapper such as
    # bash -c): the review of HEAD is required.
    if [ "$found" = 0 ] && printf '%s\n' "$text" | grep -qE '(^|[^[:alnum:]_-])(git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create)([^[:alnum:]_-]|$)'; then
        resolve_commit "$dir" HEAD
    fi
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
    local input="$1" command cwd root target reason out rc=0
    command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
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
    # message is used when that call is absent.
    msg="$(jq -rs '
        ([.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "SubagentHandback") | .input.message] | last)
        // ([.[] | select(.type == "assistant") | .message.content | if type == "array" then map(select(.type == "text") | .text) | join("") else . end] | last)
        // empty' "$transcript" 2>/dev/null || true)"
    if [ -z "$msg" ]; then
        msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"
    fi
    if [ -z "$msg" ]; then
        echo "local review not recorded: no final report in the reviewer's transcript" >&2
        return 0
    fi
    # The SHA the reviewer was started on: the `SHA: <full sha>` line of the first user message
    # of its transcript (the session's four inputs), before anything the reviewer read.
    sha="$(jq -rs '[.[] | select(.type == "user")][0] | .message.content | if type == "array" then map(.text // "") | join("\n") else . end // empty' "$transcript" 2>/dev/null \
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

    review() { # review <sha> <verdict> [extra report lines...]
        local s="$1" v="$2"
        shift 2
        { printf 'VERDICT: %s\nREVIEWED_SHA: %s\nPROTECTED: none\n' "$v" "$s"; printf '%s\n' "$@"; } | (cd "$repo" && "$GATE" record "$s") >/dev/null 2>&1 || true
    }
    # expect <name> <want exit> <command>
    expect() {
        name="$1"; want="$2"; rc=0
        jq -n --arg c "$3" --arg d "$repo" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
            | bash "$hook" >/dev/null 2>"$tmp/err" || rc=$?
        if [ "$rc" = "$want" ]; then echo "ok   $name (exit $rc)"; else echo "FAIL $name: expected exit $want, got $rc: $(head -c 300 "$tmp/err")" >&2; fails=$((fails + 1)); fi
    }

    expect "non-push command passes" 0 "git status"
    expect "a mention of git push needs the review of HEAD" 2 "echo git push"
    expect "push with no review blocks" 2 "git push -u origin main"
    expect "gh pr create with no review blocks" 2 "gh pr create --base main --body-file b.md"
    expect "wrapped push with no review blocks" 2 "bash -c 'git push'"
    expect "git alias that pushes blocks" 2 "git sneak"
    expect "git -c alias blocks" 2 "git -c alias.p=push p"
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
    review "$sha" ESCALATE_TO_HUMAN "1. [important] a.kt (f): item 13: suspicion; fix"
    expect "important without disposition blocks" 2 "git push"
    (cd "$repo" && "$GATE" disposition "$sha" "board record some-slug") >/dev/null 2>&1
    expect "important with disposition allows" 0 "git push"
    git -C "$repo" commit -q --allow-empty -m three
    expect "a new commit needs a new review" 2 "git push"

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
    # Without jq the input cannot be read: block anything that mentions a push or a PR creation.
    if printf '%s' "$INPUT" | grep -qE 'git.*push|gh.*pr.*create'; then
        echo "Blocked: jq is needed to check the local review before a push or PR and is not installed." >&2
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
