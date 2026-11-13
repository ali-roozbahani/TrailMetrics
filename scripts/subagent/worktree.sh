#!/usr/bin/env bash
# The orchestrator's tool for an implementer subagent's git worktree (tm-agent-loop, "Subagents"):
# create the worktree from a local branch, take the implementer's commits back into the task branch,
# remove it. Run it from the main clone, never from inside a worktree, and never as the implementer
# (the implementer's guard, scripts/subagent/guard.sh, refuses this script to it).
#
#   scripts/subagent/worktree.sh create <name> --from <local branch> --allow <path>... [--ios] [--android]
#   scripts/subagent/worktree.sh take <name>
#   scripts/subagent/worktree.sh remove <name> [--force]
#   scripts/subagent/worktree.sh list
#   scripts/subagent/worktree.sh check-path <worktree dir> <repo-relative path>    (used by the guard)
#   scripts/subagent/worktree.sh --self-test
#
# create <name>: `<name>` is lowercase letters, digits and `-`. It makes the worktree
#   `<main clone>/.claude/worktrees/<name>` (inside the clone, so the subagent's file tools work
#   there without a prompt; the folder is git-ignored by the repository's .gitignore and is not part of
#   any Gradle build) on a new local branch `chore/wt-<name>` that starts at the tip of `--from`
#   (the committed state: uncommitted changes of the main clone are not in it). Each `--allow` is a
#   repo-relative path the implementer may write: a directory (a prefix) or one file; no `..`, no
#   absolute path, no glob, nothing under `.git`. At least one is required. The record is written to
#   the worktree's own git directory (`<git dir>/worktrees/<name>/tm-subagent/`: `allowed`, `from`,
#   `base`, `branch`), which no file tool of the implementer is allowed to write, and is what the
#   guard and `take` read.
#   `--ios` / `--android` put a symbolic link to the git-ignored iOS secrets config / `local.properties`
#   of the main clone into the worktree, so the module's build works there. The files are never read,
#   printed or copied by this script; a missing one refuses. The worktree path differs from the root
#   the deny rules of .claude/settings.json name, so reading the link through the worktree needs its
#   own deny rule (the guard also refuses it).
#   The branch name has the `chore/` prefix, is local only and is never pushed (no queue entry, no PR).
#   The implementer's task file goes next to the worktree, `<main clone>/.claude/worktrees/<name>.task.md`
#   (written by the orchestrator, git-ignored with the folder, inside the project directory so the
#   subagent can read it, and outside the worktree so it never shows up in its `git status`); `create`
#   prints the path and `remove` deletes the file.
#
# take <name>: brings the commits the implementer made since the last take (or since the start) into
#   the branch the worktree was created from, which must be checked out and clean in the main clone,
#   one commit at a time with `git cherry-pick`, oldest first. Refuses, and changes nothing, when: the
#   worktree has uncommitted changes, is not on its branch, or a commit is a merge or changes a file
#   outside the allowed paths. A conflict or any failing pick ends with the branch reset to where it
#   was before the take (only our own picks are discarded) and exit 1. On success the take's end point
#   becomes the new `base`, so a second take brings only newer commits.
#
# remove <name>: removes the links, the worktree and its branch. Refuses while the worktree has
#   uncommitted changes or commits that were not taken, unless `--force`.
#
# Exit: 0 ok (check-path: allowed), 1 refused (reason on stderr; check-path: not allowed),
#   2 usage error. Bash 3.2 compatible.
set -u

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
NAME_RE='^[a-z0-9][a-z0-9-]{0,40}$'
USAGE="usage: scripts/subagent/worktree.sh create <name> --from <local branch> --allow <path>... [--ios] [--android]
       scripts/subagent/worktree.sh take <name> | remove <name> [--force] | list
       scripts/subagent/worktree.sh check-path <worktree dir> <path> | --self-test"

usage() { echo "$USAGE" >&2; exit 2; }
refuse() { echo "worktree: refused: $*" >&2; exit 1; }

main_root() { # the main clone's top directory, from the current directory (a worktree resolves to the main clone)
    local common
    common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    (cd "$common/.." && pwd -P)
}

wt_root_dir() { # the worktree folder, canonical (git lists canonical paths), created when missing
    local d="${TM_WORKTREE_DIR:-$MAIN/.claude/worktrees}"
    mkdir -p "$d" 2>/dev/null && (cd "$d" && pwd -P) || echo "$d"
}

record_dir() { # record_dir <worktree dir>: the worktree's own tm-subagent directory
    git -C "$1" rev-parse --path-format=absolute --git-path tm-subagent 2>/dev/null
}

# normalize_allow <path>: prints the stored form or returns 1.
normalize_allow() {
    local p="$1" part rest
    while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
    p="${p%/}"
    [ -n "$p" ] || return 1
    case "$p" in /* | *'*'* | *'?'* | *'['* | *'\'*) return 1 ;; esac
    case "$p" in *[[:cntrl:]]*) return 1 ;; esac
    rest="$p"
    while [ -n "$rest" ]; do
        part="${rest%%/*}"
        case "$part" in '' | . | .. | .git) return 1 ;; esac
        if [ "$part" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    done
    printf '%s' "$p"
}

# path_allowed <record dir> <repo-relative path>: 0 when an allowed entry is the path or a directory above it.
path_allowed() {
    local rec="$1" p="$2" e
    [ -f "$rec/allowed" ] || return 1
    case "$p" in '' | /* | .. | ../* | */.. | */../* | .git | .git/* | */.git | */.git/*) return 1 ;; esac
    while IFS= read -r e || [ -n "$e" ]; do
        [ -n "$e" ] || continue
        if [ "${e%/}" != "$e" ]; then
            case "$p" in "$e"*) return 0 ;; esac
        else
            [ "$p" = "$e" ] && return 0
        fi
    done < "$rec/allowed"
    return 1
}

find_wt() { # find_wt <name>: sets WT, REC, FROM, BASE, BRANCH or refuses
    local name="$1"
    [[ "$name" =~ $NAME_RE ]] || refuse "'$name' is not a worktree name (lowercase letters, digits, '-')"
    WT="$(wt_root_dir)/$name"
    [ -d "$WT" ] || refuse "no worktree '$name' at $WT"
    git worktree list --porcelain | grep -qxF "worktree $WT" || refuse "$WT is not a registered worktree of this clone"
    REC="$(record_dir "$WT")" || refuse "cannot read the git directory of $WT"
    [ -f "$REC/allowed" ] && [ -f "$REC/from" ] && [ -f "$REC/base" ] && [ -f "$REC/branch" ] \
        || refuse "$WT has no complete tm-subagent record (not created by this script?)"
    FROM="$(cat "$REC/from")"; BASE="$(cat "$REC/base")"; BRANCH="$(cat "$REC/branch")"
}

require_main_clone() {
    MAIN="$(main_root)" || refuse "not inside a git work tree"
    [ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
        || refuse "run this from the main clone, not from a linked worktree"
}

cmd_create() {
    local name="${1:-}" from="" ios=0 android=0 n allowed="" branch dir sha e rec src
    [ -n "$name" ] || usage
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --from) [ $# -ge 2 ] || usage; from="$2"; shift 2 ;;
            --allow)
                [ $# -ge 2 ] || usage
                n="$(normalize_allow "$2")" || refuse "--allow '$2' is not a repo-relative path (no '..', no absolute path, no glob, nothing under .git)"
                allowed="$allowed$n"$'\n'; shift 2 ;;
            --ios) ios=1; shift ;;
            --android) android=1; shift ;;
            *) usage ;;
        esac
    done
    [ -n "$from" ] && [ -n "$allowed" ] || usage
    [[ "$name" =~ $NAME_RE ]] || refuse "'$name' is not a worktree name (lowercase letters, digits, '-')"
    require_main_clone
    git show-ref --verify --quiet "refs/heads/$from" || refuse "--from '$from' is not a local branch"
    branch="chore/wt-$name"
    dir="$(wt_root_dir)/$name"
    git show-ref --verify --quiet "refs/heads/$branch" && refuse "the branch $branch already exists"
    [ ! -e "$dir" ] || refuse "$dir already exists"
    if [ "$ios" = 1 ]; then
        src="$MAIN/iosApp/TrailMetrics/Secrets.xcconfig"
        [ -f "$src" ] || refuse "--ios: the iOS secrets config is missing in the clone (README, \"iOS\", step 2); not created, not read"
    fi
    if [ "$android" = 1 ]; then
        [ -f "$MAIN/local.properties" ] || refuse "--android: local.properties is missing in the clone (README, \"Android\", step 2)"
    fi
    sha="$(git rev-parse "refs/heads/$from")"
    mkdir -p "$(dirname "$dir")" || refuse "cannot create $(dirname "$dir")"
    git worktree add -q -b "$branch" "$dir" "$sha" || refuse "git worktree add failed"
    rec="$(record_dir "$dir")" || refuse "cannot read the new worktree's git directory"
    mkdir -p "$rec"
    # A directory that exists in the start commit is stored with a trailing slash (a prefix).
    : > "$rec/allowed"
    printf '%s' "$allowed" | while IFS= read -r e; do
        [ -n "$e" ] || continue
        if [ -d "$dir/$e" ]; then printf '%s/\n' "$e" >> "$rec/allowed"; else printf '%s\n' "$e" >> "$rec/allowed"; fi
    done
    printf '%s\n' "$from" > "$rec/from"
    printf '%s\n' "$sha" > "$rec/base"
    printf '%s\n' "$branch" > "$rec/branch"
    if [ "$ios" = 1 ]; then mkdir -p "$dir/iosApp/TrailMetrics" && ln -s "$src" "$dir/iosApp/TrailMetrics/Secrets.xcconfig" || refuse "cannot link the iOS secrets config"; fi
    if [ "$android" = 1 ]; then ln -s "$MAIN/local.properties" "$dir/local.properties" || refuse "cannot link local.properties"; fi
    echo "created worktree $dir"
    echo "branch: $branch (local only, from $from at $sha)"
    echo "allowed paths:"
    sed 's/^/  /' "$rec/allowed"
    [ "$ios" = 0 ] || echo "iOS secrets config: linked, not read"
    [ "$android" = 0 ] || echo "local.properties: linked, not read"
    echo "task file for the implementer: $(wt_root_dir)/$name.task.md (write it before starting the implementer)"
    echo "The implementer works in $dir; the orchestrator brings its commits back with: scripts/subagent/worktree.sh take $name"
}

cmd_take() {
    local name="${1:-}" head0 cur tip commits c parents f files n=0 picked
    [ -n "$name" ] && [ $# -eq 1 ] || usage
    require_main_clone
    find_wt "$name"
    [ -z "$(git -C "$WT" status --porcelain)" ] || refuse "the worktree has uncommitted changes; the implementer commits first: $(git -C "$WT" status --porcelain | head -3 | tr '\n' ';')"
    [ "$(git -C "$WT" symbolic-ref --short -q HEAD)" = "$BRANCH" ] || refuse "the worktree is not on its branch $BRANCH"
    cur="$(git symbolic-ref --short -q HEAD)" || cur=""
    [ "$cur" = "$FROM" ] || refuse "check out $FROM in the main clone first (it is on '${cur:-a detached HEAD}')"
    [ -z "$(git status --porcelain)" ] || refuse "the main clone's tree is not clean"
    for f in CHERRY_PICK_HEAD MERGE_HEAD REBASE_HEAD; do
        [ ! -e "$(git rev-parse --path-format=absolute --git-path "$f")" ] || refuse "a $f is in progress in the main clone"
    done
    tip="$(git rev-parse "refs/heads/$BRANCH")"
    git merge-base --is-ancestor "$BASE" "$tip" || refuse "the base $BASE is not an ancestor of $BRANCH (history was rewritten)"
    commits="$(git rev-list --reverse "$BASE..$tip")"
    if [ -z "$commits" ]; then echo "nothing to take: $BRANCH has no commit after $BASE"; return 0; fi
    for c in $commits; do
        parents="$(git rev-list --parents -n 1 "$c" | wc -w | tr -d ' ')"
        [ "$parents" -le 2 ] || refuse "commit $c is a merge commit"
        files="$(git diff-tree -r --no-commit-id --name-only --no-renames --root "$c")"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            path_allowed "$REC" "$f" || refuse "commit $c changes '$f', outside the allowed paths"
        done <<< "$files"
        # Renames and deletes name their old path in the same list (--no-renames), so both are checked.
        n=$((n + 1))
    done
    head0="$(git rev-parse HEAD)"
    picked=0
    for c in $commits; do
        if ! git cherry-pick "$c" >/dev/null 2>"${TMPDIR:-/tmp}/wt-pick.$$"; then
            echo "worktree: the pick of $c failed: $(head -2 "${TMPDIR:-/tmp}/wt-pick.$$" | tr '\n' ' ')" >&2
            rm -f "${TMPDIR:-/tmp}/wt-pick.$$"
            git cherry-pick --abort >/dev/null 2>&1
            git reset -q --hard "$head0"
            refuse "the take of $name was undone ($picked of $n commits had applied); $FROM is at $head0 again. Remove the worktree (--force) and create it again from the new tip of $FROM, or take sooner."
        fi
        picked=$((picked + 1))
    done
    rm -f "${TMPDIR:-/tmp}/wt-pick.$$"
    printf '%s\n' "$tip" > "$REC/base"
    echo "took $n commit(s) of $BRANCH into $FROM, one at a time: $head0..$(git rev-parse HEAD)"
}

cmd_remove() {
    local name="${1:-}" force=0 tip
    [ -n "$name" ] || usage
    shift
    while [ $# -gt 0 ]; do
        case "$1" in --force) force=1; shift ;; *) usage ;; esac
    done
    require_main_clone
    find_wt "$name"
    tip="$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" || tip=""
    if [ "$force" = 0 ]; then
        [ -z "$(git -C "$WT" status --porcelain)" ] || refuse "the worktree has uncommitted changes (--force discards them)"
        [ "$tip" = "$BASE" ] || refuse "$BRANCH has commits that were not taken (take them, or --force discards them)"
    fi
    # The links are ours: remove them first so a worktree removal never follows them.
    [ ! -L "$WT/iosApp/TrailMetrics/Secrets.xcconfig" ] || rm -f -- "$WT/iosApp/TrailMetrics/Secrets.xcconfig"
    [ ! -L "$WT/local.properties" ] || rm -f -- "$WT/local.properties"
    if [ "$force" = 1 ]; then
        git worktree remove --force "$WT" || refuse "git worktree remove failed"
    else
        git worktree remove "$WT" || refuse "git worktree remove failed (untracked files? --force)"
    fi
    git worktree prune
    rm -f -- "$(wt_root_dir)/$name.task.md"
    if git branch -D "$BRANCH" >/dev/null 2>&1; then
        echo "removed worktree $WT and branch $BRANCH"
    else
        echo "removed worktree $WT, but the branch $BRANCH could not be deleted (delete it with git branch -D $BRANCH)" >&2
        return 1
    fi
}

cmd_list() {
    local line path name rec base tip n
    require_main_clone
    echo "worktree list: $(wt_root_dir)"
    git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r path; do
        case "$path" in "$(wt_root_dir)"/*) ;; *) continue ;; esac
        name="$(basename "$path")"
        rec="$(record_dir "$path")" || continue
        [ -f "$rec/base" ] || { echo "$name  (no record)"; continue; }
        base="$(cat "$rec/base")"; tip="$(git -C "$path" rev-parse HEAD)"
        n="$(git rev-list --count "$base..$tip")"
        echo "$name  branch $(cat "$rec/branch")  from $(cat "$rec/from")  untaken commits: $n  uncommitted: $(git -C "$path" status --porcelain | wc -l | tr -d ' ')"
    done
}

cmd_check_path() { # check-path <worktree dir> <path>
    local dir="${1:-}" p="${2:-}" rec
    [ $# -eq 2 ] || usage
    rec="$(record_dir "$dir")" || exit 1
    [ -f "$rec/allowed" ] || exit 1
    path_allowed "$rec" "$p"
}

self_test() {
    local tmp fails=0 repo out rc main_tip
    tmp="$(cd "$(mktemp -d)" && pwd -P)"
    TMP_ROOT="$tmp"
    trap 'rm -rf -- "$TMP_ROOT"' EXIT
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null TM_WORKTREE_DIR="$tmp/wts"
    check() { # check <description> <expected substring> <expected exit> <command...>
        local d="$1" want="$2" wantrc="$3"
        shift 3
        out="$("$@" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" = "$wantrc" ] && { [ -z "$want" ] || printf '%s' "$out" | grep -qF -- "$want"; }; then echo "ok   $d"; else
            echo "FAIL $d: expected exit $wantrc and '$want', got exit $rc:" >&2
            printf '%s\n' "$out" | sed 's/^/       /' >&2; fails=$((fails + 1)); fi
    }
    repo="$tmp/repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name t
    mkdir -p "$repo/src" "$repo/docs" "$repo/iosApp/TrailMetrics"
    echo one > "$repo/src/a.txt"; echo two > "$repo/docs/b.txt"; echo three > "$repo/c.txt"
    printf 'iosApp/TrailMetrics/Secrets.xcconfig\nlocal.properties\n' > "$repo/.gitignore"
    git -C "$repo" add -A && git -C "$repo" commit -q -m base
    git -C "$repo" switch -q -c chore/task
    w() { (cd "$repo" && bash "$SELF" "$@"); }
    local wt="$tmp/wts/impl"
    # In the worktree, commit as the implementer would.
    commit_in() { # commit_in <file> <content>
        mkdir -p "$(dirname "$wt/$1")"; printf '%s\n' "$2" > "$wt/$1"
        git -C "$wt" add -A && git -C "$wt" commit -q -m "change $1"
    }

    check "create refuses a bad name" "is not a worktree name" 1 w create Bad_Name --from chore/task --allow src
    check "create refuses a missing --from branch" "is not a local branch" 1 w create impl --from nope --allow src
    check "create refuses '..' in an allowed path" "is not a repo-relative path" 1 w create impl --from chore/task --allow ../x
    check "create refuses an absolute allowed path" "is not a repo-relative path" 1 w create impl --from chore/task --allow /etc
    check "create refuses a glob" "is not a repo-relative path" 1 w create impl --from chore/task --allow 'src/*'
    check "create refuses .git" "is not a repo-relative path" 1 w create impl --from chore/task --allow .git/hooks
    check "create needs an allowed path" "usage:" 2 w create impl --from chore/task
    check "create refuses --ios without the secrets config" "the iOS secrets config is missing" 1 w create impl --from chore/task --allow src --ios
    check "create refuses --android without local.properties" "local.properties is missing" 1 w create impl --from chore/task --allow src --android
    : > "$repo/iosApp/TrailMetrics/Secrets.xcconfig"; : > "$repo/local.properties"
    check "create makes the worktree" "created worktree $wt" 0 w create impl --from chore/task --allow src --allow docs/new.txt --ios --android
    check "create named the task file next to the worktree" "$tmp/wts/impl.task.md" 0 printf '%s' "$out"
    check "the allowed paths are stored, a directory with a slash" "src/" 0 cat "$repo/.git/worktrees/impl/tm-subagent/allowed"
    check "a file entry is stored as given" "docs/new.txt" 0 cat "$repo/.git/worktrees/impl/tm-subagent/allowed"
    check "the secrets link is a symbolic link" "link" 0 bash -c "[ -L '$wt/iosApp/TrailMetrics/Secrets.xcconfig' ] && [ -L '$wt/local.properties' ] && echo link"
    echo task > "$tmp/wts/impl.task.md"
    check "the branch is chore/wt-impl" "chore/wt-impl" 0 git -C "$wt" symbolic-ref --short HEAD
    check "create refuses a second worktree of the same name" "already exists" 1 w create impl --from chore/task --allow src
    check "check-path: a file under an allowed directory" "" 0 w check-path "$wt" src/deep/x.kt
    check "check-path: the allowed file" "" 0 w check-path "$wt" docs/new.txt
    check "check-path: another file of that directory is not allowed" "" 1 w check-path "$wt" docs/b.txt
    check "check-path: a sibling with the same prefix is not allowed" "" 1 w check-path "$wt" src2/x
    check "check-path: .git is never allowed" "" 1 w check-path "$wt" src/.git/config
    check "check-path: a '..' path is not allowed" "" 1 w check-path "$wt" src/../c.txt
    check "check-path: a directory that is not a worktree" "" 1 w check-path "$tmp" src/a.txt
    check "list names the worktree" "impl  branch chore/wt-impl" 0 w list

    check "take with nothing to take" "nothing to take" 0 w take impl
    commit_in src/a.txt "one changed"
    commit_in src/new.txt "new"
    check "take brings both commits, one at a time" "took 2 commit(s)" 0 w take impl
    check "the task branch has the change" "one changed" 0 cat "$repo/src/a.txt"
    check "a second take has nothing new" "nothing to take" 0 w take impl
    main_tip="$(git -C "$repo" rev-parse HEAD)"

    commit_in c.txt "outside"
    check "take refuses a commit outside the allowed paths" "outside the allowed paths" 1 w take impl
    check "a refused take changes nothing" "$main_tip" 0 git -C "$repo" rev-parse HEAD
    git -C "$wt" reset -q --hard HEAD~1
    echo dirty >> "$wt/src/a.txt"
    check "take refuses uncommitted changes" "uncommitted changes" 1 w take impl
    git -C "$wt" checkout -q -- src/a.txt

    # A conflict undoes the whole take.
    commit_in src/a.txt "conflicting"
    commit_in src/second.txt "second"
    echo "main side" > "$repo/src/a.txt"; git -C "$repo" commit -q -am "main moved"
    main_tip="$(git -C "$repo" rev-parse HEAD)"
    check "a conflicting pick is refused and undone" "was undone" 1 w take impl
    check "the task branch is where it was" "$main_tip" 0 git -C "$repo" rev-parse HEAD
    check "the main tree is clean after the undo" "" 0 test -z "$(git -C "$repo" status --porcelain)"
    check "remove refuses commits that were not taken" "were not taken" 1 w remove impl
    check "take must run on the --from branch" "check out chore/task" 1 bash -c "cd '$repo' && git switch -q main && bash '$SELF' take impl"
    git -C "$repo" switch -q chore/task

    # A merge commit is refused.
    git -C "$wt" reset -q --hard "$(cat "$repo/.git/worktrees/impl/tm-subagent/base")"
    git -C "$wt" switch -q -c side && commit_in src/side.txt side && git -C "$wt" switch -q chore/wt-impl
    commit_in src/main-side.txt ms
    git -C "$wt" merge -q --no-ff side -m merge >/dev/null 2>&1
    check "take refuses a merge commit" "is a merge commit" 1 w take impl
    git -C "$wt" reset -q --hard "$(cat "$repo/.git/worktrees/impl/tm-subagent/base")"

    check "remove removes the worktree and its branch" "removed worktree $wt" 0 w remove impl
    check "remove deleted the task file" "gone" 0 bash -c "[ ! -e '$tmp/wts/impl.task.md' ] && echo gone"
    check "the directory is gone" "gone" 0 bash -c "[ ! -e '$wt' ] && echo gone"
    check "the branch is gone" "" 1 git -C "$repo" show-ref --verify --quiet refs/heads/chore/wt-impl
    check "the clone's secrets config is untouched" "ok" 0 bash -c "[ -f '$repo/iosApp/TrailMetrics/Secrets.xcconfig' ] && [ -f '$repo/local.properties' ] && echo ok"
    check "remove of an unknown worktree is refused" "no worktree" 1 w remove impl
    check "take from inside a linked worktree is refused" "main clone" 1 bash -c "cd '$repo' && bash '$SELF' create other --from chore/task --allow src >/dev/null && cd '$tmp/wts/other' && bash '$SELF' take other"
    check "remove --force discards untaken work" "removed worktree" 0 bash -c "cd '$repo' && echo x > '$tmp/wts/other/src/x.txt' && bash '$SELF' remove other --force"

    if [ "$fails" -eq 0 ]; then echo "worktree.sh self-test: all passed"; else echo "worktree.sh self-test: $fails failed" >&2; fi
    [ "$fails" -eq 0 ]
}

case "${1:-}" in
    --self-test) [ $# -eq 1 ] || usage; self_test; exit $? ;;
    create) shift; cmd_create "$@" ;;
    take) shift; cmd_take "$@" ;;
    remove) shift; cmd_remove "$@" ;;
    list) [ $# -eq 1 ] || usage; cmd_list ;;
    check-path) shift; cmd_check_path "$@" ;;
    *) usage ;;
esac
